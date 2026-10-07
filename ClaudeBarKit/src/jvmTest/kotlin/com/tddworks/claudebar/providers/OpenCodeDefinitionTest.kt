package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.CLIExecutor
import com.tddworks.claudebar.datasources.CLIResult
import com.tddworks.claudebar.datasources.Fetch
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.quotas.Left
import com.tddworks.claudebar.quotas.Money
import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.CsvSource
import org.junit.jupiter.params.provider.ValueSource
import java.io.File
import java.math.BigDecimal
import java.nio.file.Files
import java.time.Instant
import java.util.Collections
import kotlin.math.max

/** OpenCode Go as data: the usage API, and — with no key — one read-only query of opencode's own database, worked out by SQLite. */
class OpenCodeDefinitionTest {
    private val usage = """{"usage":{"rolling":{"status":"ok","percent":1,"resetsAt":"2026-08-24T15:34:00.000Z"},"weekly":{"status":"ok","percent":17,"resetsAt":"2026-08-29T00:00:00Z"},"monthly":{"status":"rate-limited","percent":98}}}"""

    /** Apr 1, 2026 12:00 UTC. */
    private val now = 1775044800.0

    /** What `opencode db … --format json` prints for the query: one row. */
    private val localRow = """[{"now_ms":1775044800000,"five_hour_cost":2.5,"five_hour_oldest_ms":1775037600000,"weekly_cost":7.5,"week_end_ms":1775433600000,"monthly_cost":15,"month_start_ms":1773502200000,"month_end_ms":1776177000000}]"""

    private val stubs = mutableListOf<StubbedProvider>()

    /** What a request or a run did that OpenCode Go's definition must never do. */
    private val wrong: MutableList<String> = Collections.synchronizedList(mutableListOf())

    @AfterEach
    fun cleanUp() {
        stubs.forEach { it.cleanUp() }
        assertEquals(emptyList<String>(), wrong)
    }

    /** `opencode` on this Mac, found when [available], printing [output] and exiting with [exit]. */
    private inner class OpenCodeCLI(private val available: Boolean, private val output: String, private val exit: Int) : CLIExecutor {
        override fun locate(binary: String): String? = if (available) "/test/opencode" else null

        override suspend fun execute(
            binary: String, args: List<String>, input: String?, timeoutSeconds: Double,
            workingDirectory: String?, autoResponses: Map<String, String>,
        ): CLIResult {
            if (binary != "opencode") wrong += "ran $binary"
            if (timeoutSeconds != 15.0) wrong += "timeout $timeoutSeconds"
            if (args.firstOrNull() != "db") wrong += "args start ${args.firstOrNull()}"
            if (args.takeLast(2) != listOf("--format", "json")) wrong += "args end ${args.takeLast(2)}"
            // One fixed query, shown word for word on Import.
            if (args.size != 4) wrong += "${args.size} args"
            return CLIResult(output, exit)
        }
    }

    private fun make(
        body: String = usage, status: Int = 200, key: String? = "personal", local: String = localRow, exit: Int = 0,
        clock: Double = now, env: Map<String, String>? = null, available: Boolean = true,
        vault: MemoryVault = MemoryVault(),
    ): Provider {
        val stub = StubbedProvider().also { stubs += it }
        stub.http.answer = { call ->
            if (call.url != "https://opencode.ai/zen/go/v1/usage") wrong += "asked ${call.url}"
            if (call.timeoutSeconds != 15.0) wrong += "HTTP timeout ${call.timeoutSeconds}"
            if (call.headers["Authorization"] !in listOf("Bearer personal", "Bearer work", "Bearer file-key")) wrong += "sent ${call.headers["Authorization"]}"
            Response(status, body = body.encodeToByteArray())
        }
        stub.commands = OpenCodeCLI(available, local, exit)
        stub.environment = env ?: (if (key != null) mapOf("OPENCODE_API_KEY" to key) else emptyMap())
        stub.now = { clock }
        val definition = TestDefinitions.builtIn("opencode-go")
        return stub.make(definition, vault = vault)
    }

    private fun usd(amount: String) = Money(BigDecimal(amount).movePointRight(9).longValueExact(), "USD")

    private fun RefreshOutcome.failure(): UsageError {
        assertTrue(this is RefreshOutcome.Failed, "expected a failure, got $this")
        return (this as RefreshOutcome.Failed).error
    }

    @Test
    fun `should show the 5-hour, weekly and monthly quotas with their resets and windows when OpenCode Go answers`() {
        val p = make()
        assertEquals("OpenCode Go", p.name)
        assertTrue(p.defaultAccount.isEnabled)
        val qs = p.refreshPlain().usage().quotas
        assertEquals(listOf(99.0, 83.0, 0.0), qs.map { it.percentRemaining })
        assertEquals(listOf(QuotaType.Session, QuotaType.Weekly, QuotaType.TimeLimit("Monthly")), qs.map { it.quotaType })
        assertEquals(1787585640.0, qs[0].resetsAtSeconds)
        assertEquals(18000.0, qs[0].window?.lengthSeconds)
        assertEquals(604800.0, qs[1].window?.lengthSeconds)
        assertNull(qs[2].window?.lengthSeconds)
    }

    @ParameterizedTest
    @CsvSource(delimiter = '|', value = ["rolling|\"12.5\"|87.5", "weekly|130|0.0", "monthly|-4|100.0"])
    fun `should keep the percent left between 0 and 100 when OpenCode Go reports one window, as a number or text`(window: String, percent: String, left: Double) {
        val qs = make(body = "{\"usage\":{\"$window\":{\"percent\":$percent}}}").refreshPlain().usage().quotas
        assertEquals(1, qs.size)
        assertEquals(left, qs[0].percentRemaining)
    }

    @ParameterizedTest
    @ValueSource(strings = ["<html>", "{}", """{"usage":{}}"""])
    fun `should fail to read usage when OpenCode Go answers with no usage`(body: String) {
        make(body = body).refreshPlain().failure()
    }

    @Test
    fun `should ask to refresh the API key, not read the local database, when OpenCode Go refuses the key`() {
        assertEquals(
            UsageError.SessionExpired("Run `opencode auth login` and pick OpenCode Zen to refresh your API key."),
            make(status = 401).refreshPlain().failure(),
        )
    }

    @Test
    fun `should say a subscription is required when OpenCode Go forbids the key`() {
        assertEquals(UsageError.SubscriptionRequired, make(status = 403).refreshPlain().failure())
    }

    @Test
    fun `should show the server error, not read the local database, when OpenCode Go is down`() {
        assertEquals(UsageError.ExecutionFailed("HTTP error: 500"), make(status = 500).refreshPlain().failure())
    }

    @Test
    fun `should show a rate limit, not read the local database, when OpenCode Go is rate-limiting`() {
        assertEquals("rateLimited", make(status = 429).refreshPlain().failure().tag)
    }

    @Test
    fun `should show dollars left of each cap from opencode's own database when there is no key`() {
        val p = make(key = null)
        assertTrue(p.isPlainAvailable())
        val qs = p.refreshPlain().usage().quotas
        assertEquals(listOf(QuotaType.Session, QuotaType.Weekly, QuotaType.TimeLimit("Monthly")), qs.map { it.quotaType })
        assertEquals(Left.Balance(usd("9.50"), usd("12")), qs[0].left)
        assertEquals(Left.Balance(usd("22.50"), usd("30")), qs[1].left)
        assertEquals(Left.Balance(usd("45.00"), usd("60")), qs[2].left)
        assertEquals(1775037600.0 + 18000, qs[0].resetsAtSeconds) // the oldest spend in 5h, plus 5h
        assertEquals(1775433600.0, qs[1].resetsAtSeconds)
        assertEquals(1776177000.0, qs[2].resetsAtSeconds)
        assertEquals(2_674_800.0, qs[2].window?.lengthSeconds) // the anchored month itself: Mar 14 to Apr 14
    }

    @Test
    fun `should show every cap full and no monthly window when nothing has been spent yet`() {
        val row = """[{"now_ms":1775044800000,"five_hour_cost":0,"five_hour_oldest_ms":null,"weekly_cost":0,"week_end_ms":1775433600000,"monthly_cost":0,"month_start_ms":null,"month_end_ms":null}]"""
        val qs = make(key = null, local = row).refreshPlain().usage().quotas
        assertEquals(listOf(100.0, 100.0, 100.0), qs.map { it.percentLeft })
        assertEquals(now + 18000, qs[0].resetsAtSeconds)
        assertNull(qs[2].resetsAtSeconds)
        assertNull(qs[2].window?.lengthSeconds)
    }

    @ParameterizedTest
    @ValueSource(doubles = [-5.0, 6.0, 20.0])
    fun `should never show less than nothing left of a cap`(cost: Double) {
        val row = "[{\"now_ms\":1775044800000,\"five_hour_cost\":$cost,\"weekly_cost\":0,\"week_end_ms\":1775433600000,\"monthly_cost\":0}]"
        val qs = make(key = null, local = row).refreshPlain().usage().quotas
        assertEquals(usd(String.format(java.util.Locale.ROOT, "%.2f", max(0.0, 12 - cost))).amountNanos, qs[0].dollarRemainingNanos)
    }

    @ParameterizedTest
    @ValueSource(strings = ["not JSON", "[]", "[{}]"])
    fun `should fail to read usage when opencode's database gives no readable spend`(local: String) {
        make(key = null, local = local).refreshPlain().failure()
    }

    @Test
    fun `should fail, never show usage, when reading opencode's database fails`() {
        assertEquals(UsageError.ExecutionFailed("`opencode` exited with code 1"), make(key = null, exit = 1).refreshPlain().failure())
    }

    @Test
    fun `should be unavailable and say opencode is not found when there is no key and no CLI`() {
        val p = make(key = null, available = false)
        assertFalse(p.isPlainAvailable())
        assertEquals(UsageError.CliNotFound("opencode"), p.refreshPlain().failure())
    }

    // The query itself, run by SQLite

    private class Message(val at: String, val cost: Double, val provider: String)

    /** The definition's query against a fixture database, as of [now] (UTC). */
    private fun query(messages: List<Message>, now: String): JsonObject {
        val definition = TestDefinitions.builtIn("opencode-go")
        val call = (definition.dataSource("local")!!.fetch as Fetch.Command).call
        val sql = call.args[1].replace("'now'", "'$now'")
        val root = Files.createTempDirectory("opencode").toFile()
        try {
            val db = File(root, "opencode.db").path
            val setup = StringBuilder("CREATE TABLE message(data TEXT, time_created INTEGER);")
            for (message in messages) {
                val ms = Instant.parse(message.at).toEpochMilli()
                setup.append("INSERT INTO message VALUES ('{\"providerID\":\"${message.provider}\",\"role\":\"assistant\",\"cost\":${message.cost},\"time\":{\"created\":$ms}}', 0);")
            }
            run("/usr/bin/sqlite3", db, setup.toString())
            val rows = Json.parseToJsonElement(run("/usr/bin/sqlite3", "-json", db, sql)) as JsonArray
            return rows.first() as JsonObject
        } finally {
            root.deleteRecursively()
        }
    }

    private fun run(vararg arguments: String): String {
        val process = ProcessBuilder(*arguments).start()
        val output = process.inputStream.bufferedReader().readText()
        process.waitFor()
        return output
    }

    private fun ms(text: String): Long = Instant.parse(text).toEpochMilli()

    private fun JsonObject.number(key: String): Double? = (this[key] as? JsonElement)?.takeUnless { it is JsonNull }?.jsonPrimitive?.doubleOrNull

    private fun JsonObject.integer(key: String): Long? = (this[key] as? JsonElement)?.takeUnless { it is JsonNull }?.jsonPrimitive?.longOrNull

    @Test
    fun `should add up the last 5 hours, the UTC week and the anchored month of OpenCode Go spend only`() {
        val row = query(
            listOf(
                Message("2026-01-31T14:30:00Z", 1.0, "opencode-go"), // the first message: the month's anchor
                Message("2026-04-29T09:00:00Z", 2.0, "opencode-go"),
                Message("2026-04-30T15:00:00Z", 4.0, "opencode-go"),
                Message("2026-05-04T10:00:00Z", 0.5, "opencode-go"),
                Message("2026-05-04T13:00:00Z", 0.25, "opencode-go"),
                Message("2026-05-04T14:00:00Z", 99.0, "another"),
            ),
            now = "2026-05-04 15:00:00",
        )
        assertEquals(0.75, row.number("five_hour_cost"))
        assertEquals(ms("2026-05-04T10:00:00Z"), row.integer("five_hour_oldest_ms"))
        assertEquals(0.75, row.number("weekly_cost"))
        assertEquals(ms("2026-05-11T00:00:00Z"), row.integer("week_end_ms")) // next UTC Monday
        // Anchored on the 31st: April has 30 days, so the month began Apr 30 14:30.
        assertEquals(ms("2026-04-30T14:30:00Z"), row.integer("month_start_ms"))
        assertEquals(ms("2026-05-31T14:30:00Z"), row.integer("month_end_ms"))
        assertEquals(4.75, row.number("monthly_cost"))
    }

    @ParameterizedTest
    @CsvSource(
        "2024-03-14T14:30:00Z, 2024-04-02 10:00:00, 2024-04-14T14:30:00Z",
        "2024-01-20T09:00:00Z, 2024-04-05 12:00:00, 2024-04-20T09:00:00Z",
        // The 31st in a 29-day February: the month ends on its last day.
        "2024-01-31T09:00:00Z, 2024-02-05 12:00:00, 2024-02-29T09:00:00Z",
    )
    fun `should start each month on the first message's day, or the month's last day when it is shorter`(first: String, now: String, end: String) {
        val row = query(listOf(Message(first, 1.0, "opencode-go")), now)
        assertEquals(ms(end), row.integer("month_end_ms"))
    }

    @Test
    fun `should show no spend and no month when there are no OpenCode Go messages`() {
        val row = query(listOf(Message("2026-05-04T14:00:00Z", 5.0, "another")), now = "2026-05-04 15:00:00")
        assertEquals(0.0, row.number("five_hour_cost"))
        assertEquals(0.0, row.number("monthly_cost"))
        assertNull(row.integer("month_start_ms"))
    }

    @Test
    fun `should use only an added login's own key, never the local database, and ask to sign in when it is gone`() {
        val vault = MemoryVault()
        val p = make(vault = vault)
        val work = p.accounts.add(filling = mapOf("apiKey" to "work")).done()
        assertEquals(listOf("api"), p.dataSources(work).map { it.kind })
        assertEquals(listOf(99.0, 83.0, 0.0), p.refreshNow(work).usage().quotas.map { it.percentRemaining })
        vault.secrets.remove("${work.id}.apiKey")
        assertEquals(UsageError.AuthenticationRequired, p.refreshNow(work).failure())
    }

    @ParameterizedTest
    @ValueSource(strings = ["opencode-go", "opencode", "both"])
    fun `should use the key opencode saved in its auth file under XDG_DATA_HOME`(entry: String) {
        val home = Files.createTempDirectory("opencode-home").toRealPath().toFile()
        try {
            val data = File(home, "data/opencode").apply { mkdirs() }
            val auth = if (entry == "both") {
                """{"opencode-go":{"key":"file-key"},"opencode":{"key":"other-key"}}"""
            } else {
                "{\"$entry\":{\"type\":\"api\",\"key\":\"file-key\"}}"
            }
            File(data, "auth.json").writeText(auth)
            val p = make(key = null, env = mapOf("XDG_DATA_HOME" to File(home, "data").path))
            assertEquals(listOf(99.0, 83.0, 0.0), p.refreshPlain().usage().quotas.map { it.percentRemaining })
        } finally {
            home.deleteRecursively()
        }
    }
}
