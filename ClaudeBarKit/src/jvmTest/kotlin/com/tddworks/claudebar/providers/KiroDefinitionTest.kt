package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.AnsweringNetwork
import com.tddworks.claudebar.datasources.CLIExecutor
import com.tddworks.claudebar.datasources.CLIResult
import com.tddworks.claudebar.datasources.DataSources
import com.tddworks.claudebar.datasources.ProcessEnvironment
import com.tddworks.claudebar.datasources.lookup.FakeCookies
import com.tddworks.claudebar.datasources.lookup.FakeDatabase
import com.tddworks.claudebar.datasources.lookup.FakeSecurity
import com.tddworks.claudebar.datasources.lookup.FakeStorage
import com.tddworks.claudebar.datasources.lookup.SecurityResult
import com.tddworks.claudebar.datasources.mapping.GraalScriptEngine
import com.tddworks.claudebar.datasources.process.DiskFiles
import com.tddworks.claudebar.datasources.process.InMemoryLoginFolders
import com.tddworks.claudebar.datasources.process.RPCTransportFactory
import com.tddworks.claudebar.datasources.AnsweringTransport
import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageError
import com.tddworks.claudebar.quotas.UsageSnapshot
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File
import java.nio.file.Files
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.Collections
import kotlin.math.abs

/** Kiro as data: `kiro-cli` given `/usage` on stdin, read by `kiro-usage.js` — the old probe's screens, with each added account in its own home. */
class KiroDefinitionTest {
    /** What a run did that Kiro's definition must never do. */
    private val wrong: MutableList<String> = Collections.synchronizedList(mutableListOf())
    private val homes = mutableListOf<File>()

    @AfterEach
    fun cleanUp() {
        homes.forEach { it.deleteRecursively() }
        assertEquals(emptyList<String>(), wrong)
    }

    /** `kiro-cli`, found when [located], printing [output]. */
    private inner class KiroCLI(private val located: Boolean, private val output: String, private val plain: Boolean) : CLIExecutor {
        override fun locate(binary: String): String? = if (located) "/usr/local/bin/kiro-cli" else null

        override suspend fun execute(
            binary: String, args: List<String>, input: String?, timeoutSeconds: Double,
            workingDirectory: String?, autoResponses: Map<String, String>,
        ): CLIResult {
            if (!plain) return CLIResult("Credits (40 of 50 covered in plan)")
            if (args.isNotEmpty()) wrong += "args $args"
            if (input != "/usage\n/quit\n") wrong += "input $input"
            if (timeoutSeconds != 30.0) wrong += "timeout $timeoutSeconds"
            if (workingDirectory != null) wrong += "ran in $workingDirectory"
            return CLIResult(output)
        }
    }

    private fun make(output: String, located: Boolean = true, workHome: String? = null, now: Double = System.currentTimeMillis() / 1000.0): Provider {
        val definition = TestDefinitions.builtIn("kiro")
        val cli = KiroCLI(located, output, plain = true)
        val work = KiroCLI(true, output, plain = false)
        val commands = { environment: ProcessEnvironment ->
            val home = environment.set["HOME"]
            if (home != null) {
                if (home != workHome) wrong += "HOME $home"
                if (environment.set["KIRO_HOME"] != "$home/.kiro") wrong += "KIRO_HOME ${environment.set["KIRO_HOME"]}"
                if (environment.set["XDG_DATA_HOME"] != "$home/.local/share") wrong += "XDG_DATA_HOME ${environment.set["XDG_DATA_HOME"]}"
                if ("KIRO_API_KEY" !in environment.unset) wrong += "kept KIRO_API_KEY"
                work
            } else {
                cli
            }
        }
        val temp = System.getProperty("java.io.tmpdir").trimEnd('/')
        val connections = DataSources(
            home = temp,
            environment = { null },
            network = AnsweringNetwork(),
            loopback = AnsweringNetwork(),
            makeCLIExecutor = { cli },
            makeCommandExecutor = commands,
            transports = RPCTransportFactory { _, _, _, _ -> AnsweringTransport() },
            directory = { "$temp/Probe" },
            processEnvironment = { emptyMap() },
            files = DiskFiles,
            processPaths = { emptyList() },
            security = FakeSecurity { SecurityResult(1, "") },
            database = FakeDatabase { _, _ -> emptyList() },
            browserCookies = FakeCookies(),
            browserStorage = FakeStorage(),
            loginShell = null,
            cloudWatch = null,
            priceCatalog = null,
            scriptEngine = GraalScriptEngine(),
            now = { now },
        )
        return Provider(
            definition = definition,
            settings = InMemoryProviderSettings(),
            makeDataSource = { source, _ -> connections.make(source, definition.id, scripts = TestDefinitions.builtIns::script) },
            folders = InMemoryLoginFolders(),
            paths = HomePaths(temp),
            isExecutable = { true },
            locate = { it },
            now = { now },
        )
    }

    private fun parse(output: String): UsageSnapshot = make(output).refreshPlain().usage()

    private fun RefreshOutcome.failure(): UsageError {
        assertTrue(this is RefreshOutcome.Failed, "expected a failure, got $this")
        return (this as RefreshOutcome.Failed).error
    }

    @Test
    fun `should show the bonus credits and the monthly credits when Kiro reports both`() {
        val output = """
        Estimated Usage | resets on 03/01 | KIRO FREE

        🎁 Bonus credits: 122.54/500 credits used, expires in 29 days

        Credits (0.00 of 50 covered in plan)
        ████████████████████████████████████████████████████████████████████████████████ 0%
        """.trimIndent()

        val snapshot = parse(output)

        assertEquals("kiro", snapshot.providerId)
        assertEquals(2, snapshot.quotas.size)

        // Bonus credits: a grant that expires, with no window of its own
        val bonus = snapshot.quotas.firstOrNull { it.quotaType == QuotaType.TimeLimit("Bonus credits") }
        assertNotNull(bonus)
        assertTrue(abs(bonus!!.percentRemaining - 75.492) < 0.01)
        assertNotNull(bonus.resetsAtSeconds)
        assertEquals("Expires in 29 days", bonus.resetText)

        // Regular credits (monthly)
        val regular = snapshot.quotas.firstOrNull { it.quotaType == QuotaType.TimeLimit("Monthly") }
        assertNotNull(regular)
        assertTrue(abs(regular!!.percentRemaining - 100.0) < 0.01)
        assertNotNull(regular.resetsAtSeconds)
        assertEquals("Resets on 03/01", regular.resetText)
    }

    @Test
    fun `should show only the bonus credits when Kiro reports no monthly credits`() {
        val snapshot = parse("🎁 Bonus credits: 250.0/500 credits used, expires in 15 days")

        assertEquals(1, snapshot.quotas.size)
        assertEquals(QuotaType.TimeLimit("Bonus credits"), snapshot.quotas[0].quotaType)
        assertTrue(abs(snapshot.quotas[0].percentRemaining - 50.0) < 0.01)
    }

    @Test
    fun `should show only the monthly credits when Kiro reports no bonus credits`() {
        val snapshot = parse("Credits (25.0 of 50 covered in plan)\nresets on 03/15")

        assertEquals(1, snapshot.quotas.size)
        assertEquals(QuotaType.TimeLimit("Monthly"), snapshot.quotas[0].quotaType)
        assertTrue(abs(snapshot.quotas[0].percentRemaining - 50.0) < 0.01)
    }

    @Test
    fun `should fail to read usage when kiro-cli prints nothing`() {
        make("").refreshPlain().failure()
    }

    @Test
    fun `should fail to read usage when kiro-cli prints no credits`() {
        make("Some random text without quota data").refreshPlain().failure()
    }

    @Test
    fun `should fail to read usage when every credit pool is zero`() {
        // No division by zero: a pool with no total is skipped.
        make("🎁 Bonus credits: 0.0/0 credits used, expires in 10 days\nCredits (0.00 of 0 covered in plan)").refreshPlain().failure()
    }

    @Test
    fun `should show no reset when Kiro gives no reset or expiry`() {
        val snapshot = parse("🎁 Bonus credits: 100.0/500 credits used\nCredits (10.0 of 50 covered in plan)")

        assertEquals(2, snapshot.quotas.size)
        for (quota in snapshot.quotas) {
            assertNull(quota.resetsAtSeconds)
            assertNull(quota.resetText)
        }
    }

    @Test
    fun `should show the credits when kiro-cli colours its output`() {
        val output = "\u001B[38;5;141mEstimated Usage\u001B[0m | resets on 03/01 | \u001B[38;5;141mKIRO FREE\u001B[0m\n" +
            "\n" +
            "\u001B[1m🎁 Bonus credits:\u001B[0m \u001B[1m122.54/500\u001B[0m credits used, expires in \u001B[1m29\u001B[0m days\n" +
            "\n" +
            "\u001B[1mCredits\u001B[0m (0.00 of 50 covered in plan)"

        val snapshot = parse(output)

        assertEquals(2, snapshot.quotas.size)
        assertTrue(abs(snapshot.quotas[0].percentRemaining - 75.492) < 0.01)
        assertTrue(abs(snapshot.quotas[1].percentRemaining - 100.0) < 0.01)
    }

    @Test
    fun `should show each added login's own credits from its own home, and ask to sign in when that home is gone`() {
        val home = Files.createTempDirectory("kiro-home").toRealPath().toFile().also { homes += it }
        val provider = make("Credits (10 of 50 covered in plan)", workHome = home.path)
        val work = provider.accounts.add(filling = mapOf("home" to home.path)).done()
        assertTrue(work.isEnabled)
        assertEquals(20.0, provider.refreshNow(work).usage().quotas.first().percentRemaining)
        assertEquals(80.0, provider.refreshPlain().usage().quotas.first().percentRemaining)
        home.deleteRecursively()
        assertEquals(UsageError.AuthenticationRequired, provider.refreshNow(work).failure())
        assertEquals(80.0, provider.refreshPlain().usage().quotas.first().percentRemaining)
    }

    @Test
    fun `should be unavailable and say kiro-cli is not found when it is not installed`() {
        val product = make("", located = false)
        assertFalse(product.isPlainAvailable())
        assertEquals(UsageError.CliNotFound("kiro-cli"), product.refreshPlain().failure())
    }

    @Test
    fun `should expire bonus credits in 29 days and reset the monthly credits next year when today is the reset day`() {
        val zone = ZoneId.systemDefault()
        fun local(year: Int, month: Int, day: Int, hour: Int = 0) = LocalDateTime.of(year, month, day, hour, 0).atZone(zone).toEpochSecond().toDouble()
        val now = local(2026, 3, 15, 12)
        val snapshot = make("Bonus credits: 100/500 used, expires in 29 days\nCredits (10 of 50 covered in plan) resets on 03/15", now = now).refreshPlain().usage()
        val bonus = snapshot.quota(QuotaType.TimeLimit("Bonus credits"))
        assertEquals(now + 29 * 86400, bonus?.resetsAtSeconds)
        assertNull(bonus?.window?.lengthSeconds) // an expiring grant is not a 7-day window
        val reset = local(2027, 3, 15)
        val monthBefore = local(2027, 2, 15)
        assertEquals(reset, snapshot.quota(QuotaType.TimeLimit("Monthly"))?.resetsAtSeconds)
        // The month that ends on the reset date — its real length, not a 30-day guess.
        assertEquals(reset - monthBefore, snapshot.quota(QuotaType.TimeLimit("Monthly"))?.windowSeconds)
    }
}
