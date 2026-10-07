package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.CLIExecutor
import com.tddworks.claudebar.datasources.CLIResult
import com.tddworks.claudebar.datasources.TEMP_HOME
import com.tddworks.claudebar.datasources.process.InMemoryLoginFolders
import com.tddworks.claudebar.datasources.testDataSources
import com.tddworks.claudebar.quotas.Left
import com.tddworks.claudebar.quotas.Money
import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageError
import com.tddworks.claudebar.quotas.UsageSnapshot
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.util.Collections

/**
 * Amp as data: `amp usage --no-color` run as a command, read by `amp-usage.js` — the old
 * probe's screens, quota for quota, with the free tier as money of its ceiling.
 */
class AmpDefinitionTest {
    /** How each run differed from `amp usage --no-color`, 8 seconds, no input, no folder — checked after every test. */
    private val wrongRuns: MutableList<String> = Collections.synchronizedList(mutableListOf())

    @AfterEach
    fun `every run is amp usage`() {
        assertEquals(emptyList<String>(), wrongRuns)
    }

    private inner class AmpCLI(
        private val output: String, private val exitCode: Int, private val executionError: UsageError?, private val located: Boolean,
    ) : CLIExecutor {
        override fun locate(binary: String): String? = if (located) "/usr/local/bin/amp" else null

        override suspend fun execute(
            binary: String, args: List<String>, input: String?, timeoutSeconds: Double,
            workingDirectory: String?, autoResponses: Map<String, String>,
        ): CLIResult {
            if (args != listOf("usage", "--no-color")) wrongRuns += "args $args"
            if (timeoutSeconds != 8.0) wrongRuns += "timeout $timeoutSeconds"
            if (input != null) wrongRuns += "input $input"
            if (workingDirectory != null) wrongRuns += "directory $workingDirectory"
            if (executionError != null) throw executionError
            return CLIResult(output, exitCode)
        }
    }

    private fun make(
        output: String, exitCode: Int = 0, executionError: UsageError? = null, located: Boolean = true, vault: MemoryVault = MemoryVault(),
    ): Provider {
        val definition = TestDefinitions.builtIn("ampcode")
        val connections = testDataSources(cli = AmpCLI(output, exitCode, executionError, located))
        return Provider(
            definition = definition, settings = InMemoryProviderSettings(),
            makeDataSource = { source, login -> connections.make(source, definition.id, vault.scoped(login), TestDefinitions.builtIns::script) },
            folders = InMemoryLoginFolders(), vault = vault, paths = HomePaths(TEMP_HOME), isExecutable = { true }, locate = { it },
        )
    }

    private fun parse(output: String): UsageSnapshot = make(output).refreshPlain().usage()

    private fun RefreshOutcome.failure(): UsageError {
        assertTrue(this is RefreshOutcome.Failed, "expected a failure, got $this")
        return (this as RefreshOutcome.Failed).error
    }

    private fun usd(dollars: Long) = Money(dollars * 1_000_000_000, "USD")

    // Sample data

    private val sampleOutput = """
        Signed in as user@example.com (username)
        Amp Free: ${'$'}17.59/${'$'}20 remaining (replenishes +${'$'}0.83/hour) [+100% bonus for 19 more days] - https://ampcode.com/settings#amp-free
        Individual credits: ${'$'}0 remaining - https://ampcode.com/settings
    """.trimIndent()

    private val sampleOutputZeroRemaining = """
        Signed in as user@example.com (username)
        Amp Free: ${'$'}0/${'$'}20 remaining (replenishes +${'$'}0.83/hour) - https://ampcode.com/settings#amp-free
        Individual credits: ${'$'}0 remaining - https://ampcode.com/settings
    """.trimIndent()

    private val sampleOutputWithIndividualCredits = """
        Signed in as user@example.com (username)
        Amp Free: ${'$'}17.59/${'$'}20 remaining (replenishes +${'$'}0.83/hour) [+100% bonus for 19 more days] - https://ampcode.com/settings#amp-free
        Individual credits: ${'$'}50 remaining - https://ampcode.com/settings
    """.trimIndent()

    private val sampleOutputIndividualCreditsOnly = """
        Signed in as user@example.com (username)
        Individual credits: ${'$'}50 remaining - https://ampcode.com/settings
    """.trimIndent()

    // Parsing

    @Test
    fun `should show the free tier as money left of its ceiling, $17_59 of $20`() {
        val snapshot = parse(sampleOutput)

        // $17.59/$20 = 87.95%
        val freeQuota = snapshot.quotas.firstOrNull { it.quotaType == QuotaType.ModelSpecific("Free") }
        assertNotNull(freeQuota)
        assertEquals(Left.Balance(Money(17_590_000_000, "USD"), usd(20)), freeQuota!!.left)
        assertEquals(87.95, freeQuota.percentLeft)
    }

    @Test
    fun `should show the email the person is signed in as`() {
        assertEquals("user@example.com", parse(sampleOutput).accountEmail)
    }

    @Test
    fun `should show 0% left when the free tier is spent`() {
        val snapshot = parse(sampleOutputZeroRemaining)

        val freeQuota = snapshot.quotas.firstOrNull { it.quotaType == QuotaType.ModelSpecific("Free") }
        assertNotNull(freeQuota)
        assertEquals(0.0, freeQuota!!.percentLeft)
    }

    @Test
    fun `should show free tier and individual credits as separate quotas`() {
        val snapshot = parse(sampleOutputWithIndividualCredits)

        assertEquals(2, snapshot.quotas.size)
        assertNotNull(snapshot.quotas.firstOrNull { it.quotaType == QuotaType.ModelSpecific("Free") })
        assertNotNull(snapshot.quotas.firstOrNull { it.quotaType == QuotaType.ModelSpecific("Individual") })
    }

    @Test
    fun `should show individual credits as $50 left, with no percentage`() {
        val snapshot = parse(sampleOutputWithIndividualCredits)

        val creditsQuota = snapshot.quotas.firstOrNull { it.quotaType == QuotaType.ModelSpecific("Individual") }
        assertEquals(50_000_000_000, creditsQuota?.dollarRemainingNanos)
        assertNull(creditsQuota?.percentLeft)
    }

    @Test
    fun `should show individual credits as $0 left, with no percentage, when they are spent`() {
        val snapshot = parse(sampleOutput)

        val creditsQuota = snapshot.quotas.firstOrNull { it.quotaType == QuotaType.ModelSpecific("Individual") }
        assertEquals(0L, creditsQuota?.dollarRemainingNanos)
        assertNull(creditsQuota?.percentLeft)
    }

    @Test
    fun `should keep the free tier's dollars so the card shows them`() {
        val freeQuota = parse(sampleOutputZeroRemaining).quotas.firstOrNull { it.quotaType == QuotaType.ModelSpecific("Free") }
        assertEquals(Left.Balance(usd(0), usd(20)), freeQuota?.left)
        assertEquals(0L, freeQuota?.dollarRemainingNanos)
    }

    @Test
    fun `should show individual credits alone when there is no free tier`() {
        val snapshot = parse(sampleOutputIndividualCreditsOnly)

        assertEquals(1, snapshot.quotas.size)
        val individualQuota = snapshot.quotas.firstOrNull { it.quotaType == QuotaType.ModelSpecific("Individual") }
        assertNotNull(individualQuota)
        assertEquals(50_000_000_000, individualQuota?.dollarRemainingNanos)
    }

    @Test
    fun `should name the free tier quota Free`() {
        val freeQuota = parse(sampleOutput).quotas.firstOrNull { it.quotaType == QuotaType.ModelSpecific("Free") }
        val type = freeQuota?.quotaType
        assertTrue(type is QuotaType.ModelSpecific, "Expected modelSpecific quota type")
        assertEquals("Free", (type as QuotaType.ModelSpecific).name)
    }

    @Test
    fun `should tag the usage and every quota as Amp's`() {
        val snapshot = parse(sampleOutput)

        assertEquals("ampcode", snapshot.providerId)
        assertTrue(snapshot.quotas.all { it.providerId == "ampcode" })
    }

    // Error handling

    @Test
    fun `should fail when Amp prints nothing`() {
        make("").refreshPlain().failure()
    }

    @Test
    fun `should fail when Amp prints something that is not its usage`() {
        make("some random text that is not amp usage output").refreshPlain().failure()
    }

    @Test
    fun `should be unavailable and say the CLI is not found when Amp is not installed`() {
        val product = make(sampleOutput, located = false)
        val account = product.defaultAccount
        assertFalse(runBlocking { product.isAvailable(account) })
        assertEquals(UsageError.CliNotFound("AmpCode"), product.refreshNow(account).failure())
    }

    @Test
    fun `should fail when Amp exits with an error`() {
        assertEquals(UsageError.ExecutionFailed("`amp` exited with code 1"), make(sampleOutput, exitCode = 1).refreshPlain().failure())
    }

    @Test
    fun `should show an added account only by its own key, never the default CLI login`() {
        val vault = MemoryVault()
        val provider = make(sampleOutput, vault = vault)
        val work = provider.accounts.add(mapOf("apiKey" to "work-key")).done()
        assertTrue(work.isEnabled)
        assertEquals(2, provider.refreshNow(work).usage().quotas.size)
        vault.secrets.remove("${work.id}.apiKey")
        assertEquals(UsageError.AuthenticationRequired, provider.refreshNow(work).failure())
        assertEquals(2, provider.refreshPlain().usage().quotas.size)
    }

    @Test
    fun `should report a failure while running as it happened`() {
        assertEquals(
            UsageError.ExecutionFailed("timeout"),
            make(sampleOutput, executionError = UsageError.ExecutionFailed("timeout")).refreshPlain().failure(),
        )
    }
}
