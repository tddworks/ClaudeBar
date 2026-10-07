package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.DataSourceError
import com.tddworks.claudebar.datasources.Fetch
import com.tddworks.claudebar.datasources.PathPattern
import com.tddworks.claudebar.datasources.SQLiteCall
import com.tddworks.claudebar.datasources.commands
import com.tddworks.claudebar.datasources.lookup.SQLiteReading
import com.tddworks.claudebar.datasources.lookup.StoredValue
import com.tddworks.claudebar.datasources.process.InMemoryLoginFolders
import com.tddworks.claudebar.datasources.testDataSources
import com.tddworks.claudebar.datasources.urls
import com.tddworks.claudebar.quotas.AccountTier
import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File
import java.nio.file.Files
import kotlin.math.abs

/** Windsurf as data: the plan Windsurf caches in its own database, read with SQLite and mapped by `windsurf-plan.js`. */
class WindsurfDefinitionTest {
    private val plan = """{"planName":"Pro","startTimestamp":1771610750000,"endTimestamp":1774029950000,"usage":{"messages":50000,"usedMessages":35650,"remainingMessages":14350,"flowActions":150000,"usedFlowActions":0,"remainingFlowActions":150000},"quotaUsage":{"dailyRemainingPercent":9,"weeklyRemainingPercent":54,"dailyResetAtUnix":1774080000,"weeklyResetAtUnix":1774166400}}"""

    private val homes = mutableListOf<File>()

    @AfterEach
    fun cleanUp() = homes.forEach { it.deleteRecursively() }

    /**
     * A home folder whose Windsurf database holds [plan] as its saved plan, stored as Windsurf
     * stores it; no database at all when [plan] is null.
     */
    private fun home(plan: String?): File {
        val home = Files.createTempDirectory("windsurf").toRealPath().toFile().also { homes += it }
        val folder = File(home, "Library/Application Support/Windsurf/User/globalStorage").apply { mkdirs() }
        if (plan == null) return home
        val quoted = plan.replace("'", "''")
        val insert = if (plan.isEmpty()) "" else "INSERT INTO ItemTable VALUES ('windsurf.settings.cachedPlanInfo', CAST('$quoted' AS BLOB));"
        sqlite3(File(folder, "state.vscdb").path, "CREATE TABLE ItemTable(key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB); $insert")
        return home
    }

    private fun make(plan: String? = this.plan, now: Double = 1773000000.0): Provider {
        val definition = TestDefinitions.builtIn("windsurf")
        val folder = home(plan)
        val connections = testDataSources(home = folder.path, database = WindsurfSQLite3, now = { now })
        return Provider(
            definition = definition,
            settings = InMemoryProviderSettings(),
            makeDataSource = { source, _ -> connections.make(source, definition.id, scripts = TestDefinitions.builtIns::script) },
            folders = InMemoryLoginFolders(),
            paths = HomePaths(folder.path),
            isExecutable = { true },
            locate = { it },
            now = { now },
        )
    }

    private fun RefreshOutcome.failure(): UsageError {
        assertTrue(this is RefreshOutcome.Failed, "expected a failure, got $this")
        return (this as RefreshOutcome.Failed).error
    }

    @Test
    fun `should be Windsurf, off until turned on, with its dashboard and icon`() {
        val windsurf = make()
        assertEquals("windsurf", windsurf.id)
        assertEquals("Windsurf", windsurf.name)
        assertEquals(false, windsurf.plainIsInLineup)
        assertEquals("https://windsurf.com/subscription/usage", windsurf.definition.profile.links.dashboard)
        assertEquals("WindsurfIcon", windsurf.definition.profile.look.icon)
    }

    @Test
    fun `should read Windsurf's own database, without running anything`() {
        val source = make().definition.dataSources.first()
        assertEquals(
            Fetch.Sqlite(
                SQLiteCall(
                    PathPattern("~/Library/Application Support/Windsurf/User/globalStorage/state.vscdb"),
                    "SELECT value FROM ItemTable WHERE key = 'windsurf.settings.cachedPlanInfo' LIMIT 1",
                ),
            ),
            source.fetch,
        )
        assertTrue(source.fetch.commands.isEmpty())
        assertTrue(source.fetch.urls.isEmpty())
    }

    @Test
    fun `should show the daily and weekly quota left, the reset times and the plan`() {
        val usage = make().refreshPlain().usage()
        val daily = usage.quotas.first { it.quotaType == QuotaType.TimeLimit("Daily") }
        assertEquals(9.0, daily.percentRemaining)
        assertEquals(1774080000.0, daily.resetsAtSeconds)
        val weekly = usage.quota(QuotaType.Weekly)!!
        assertEquals(54.0, weekly.percentRemaining)
        assertEquals(1774166400.0, weekly.resetsAtSeconds)
        assertEquals(AccountTier.Custom("Pro"), usage.accountTier)
    }

    @Test
    fun `should show messages and flow actions when the plan has no daily or weekly quota`() {
        val output = """{"planName":"Teams","endTimestamp":1774029950000,"usage":{"messages":50000,"usedMessages":35650,"flowActions":150000,"remainingFlowActions":120000}}"""
        val usage = make(output).refreshPlain().usage()
        val messages = usage.quotas.first { it.quotaType == QuotaType.ModelSpecific("Messages") }
        assertTrue(abs(messages.percentRemaining - 28.7) < 0.0001)
        assertEquals("35650/50000 used", messages.resetText)
        assertEquals(1774029950.0, messages.resetsAtSeconds)
        val flow = usage.quotas.first { it.quotaType == QuotaType.ModelSpecific("Flow actions") }
        assertEquals(80.0, flow.percentRemaining)
    }

    @Test
    fun `should say the saved plan is out of date when its period has ended, instead of showing old numbers`() {
        val output = """{"planName":"Pro","endTimestamp":1749360995879,"usage":{"messages":2500,"usedMessages":0}}"""
        val windsurf = make(output, now = 1760000000.0)
        assertEquals(UsageError.ExecutionFailed("Windsurf's saved plan is out of date. Open Windsurf to update it."), windsurf.refreshPlain().failure())
        assertEquals(DataSourceError.Step.MAPPING, windsurf.defaultAccount.lastFailedStep)
    }

    @Test
    fun `should report no data on a free plan with nothing to measure`() {
        assertEquals(UsageError.NoData, make("""{"planName":"Free"}""").refreshPlain().failure())
    }

    @Test
    fun `should ask to open Windsurf when it has saved no plan`() {
        assertEquals(UsageError.SessionExpired("Open Windsurf and sign in, so it saves your plan on this Mac."), make("").refreshPlain().failure())
    }

    @Test
    fun `should not be set up when Windsurf has never run on this Mac`() {
        assertFalse(make(null).isPlainAvailable())
    }
}

private fun sqlite3(vararg arguments: String): String {
    val process = ProcessBuilder(listOf("/usr/bin/sqlite3") + arguments).redirectErrorStream(false).start()
    val output = process.inputStream.bufferedReader().readText()
    process.waitFor()
    if (process.exitValue() != 0) throw UsageError.ExecutionFailed("Couldn't open the database")
    return output
}

/**
 * This Mac's `sqlite3`, opened read-only — the JVM's stand-in for the Mac's libsqlite3. `-json`
 * writes a BLOB's bytes as `\u00XX` escapes, so each character is one byte of it.
 */
private object WindsurfSQLite3 : SQLiteReading {
    override fun rows(path: String, query: String, name: String, limit: Int): List<Map<String, StoredValue>> {
        val output = sqlite3("-readonly", "-json", path, query).ifBlank { return emptyList() }
        return (Json.parseToJsonElement(output) as JsonArray).take(limit).map { row ->
            (row as JsonObject).mapNotNull { (column, value) ->
                val text = (value as? JsonPrimitive)?.takeUnless { it.content == "null" && !it.isString }?.content ?: return@mapNotNull null
                column to StoredValue.Bytes(ByteArray(text.length) { text[it].code.toByte() })
            }.toMap()
        }
    }
}
