package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.CLICall
import com.tddworks.claudebar.datasources.CLIResult
import com.tddworks.claudebar.datasources.Fetch
import com.tddworks.claudebar.datasources.WorkingDirectory
import com.tddworks.claudebar.datasources.process.CLICompletionRule
import com.tddworks.claudebar.datasources.process.CLIWorkingDirectory
import com.tddworks.claudebar.datasources.process.DiskFiles
import com.tddworks.claudebar.datasources.process.FakeMachine
import com.tddworks.claudebar.quotas.AccountTier
import com.tddworks.claudebar.quotas.CostUsage
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File
import java.math.BigDecimal
import java.nio.file.Files
import java.util.concurrent.atomic.AtomicInteger

/**
 * How `claude.json` runs the Claude CLI — the `cli` (`/usage`) and `cliCost` (`/cost`) data
 * sources: its environment, its completion rule, where it runs, what its screens give, when
 * `/cost` may answer, and folder-trust recovery.
 */
class ClaudeCLIDefinitionTest {
    private val claude = ClaudeHarness()

    @AfterEach
    fun cleanUp() = claude.cleanUp()

    private fun call(kind: String, definition: ProviderDefinition = TestDefinitions.builtIn("claude")): CLICall {
        val fetch = definition.dataSource(kind)?.fetch
        assertTrue(fetch is Fetch.Cli, "$kind is not a CLI data source")
        return (fetch as Fetch.Cli).call
    }

    private fun dollars(amount: String): Long = BigDecimal(amount).movePointRight(9).longValueExact()

    // The commands

    @Test
    fun `should ask the Claude CLI for -usage and for -cost, each within 20 seconds`() {
        assertEquals("claude", call("cli").cli)
        assertEquals(listOf("/usage", "--allowed-tools", ""), call("cli").args)
        assertEquals("claude", call("cliCost").cli)
        assertEquals(listOf("/cost", "--allowed-tools", ""), call("cliCost").args)
        assertEquals(20.0, call("cli").timeout)
        assertEquals(20.0, call("cliCost").timeout)
    }

    @Test
    fun `should answer the Claude CLI's start-up prompts for both screens`() {
        val expected = mapOf(
            "Esc to cancel" to "\r",
            "Ready to code here?" to "\r",
            "Press Enter to continue" to "\r",
            "ctrl+t to disable" to "\r",
            "Yes, I trust this folder" to "\r",
        )
        assertEquals(expected, call("cli").autoResponses)
        assertEquals(expected, call("cliCost").autoResponses)
    }

    @Test
    fun `should read both screens as the terminal draws them`() {
        assertEquals(CLICall.Screen.RENDERED, call("cli").screen)
        assertEquals(CLICall.Screen.RENDERED, call("cliCost").screen)
    }

    // Probe session marking (issue #222)

    @Test
    fun `should mark the Claude sessions ClaudeBar starts as its own (#222)`() {
        assertEquals("1", call("cli").environment.set["CLAUDEBAR_PROBE"])
        assertEquals("1", call("cliCost").environment.set["CLAUDEBAR_PROBE"])
    }

    // Setup Token Environment Exclusion

    @Test
    fun `should run the Claude CLI without the setup token and keep everything else`() {
        // The setup-token has only `user:inference` scope; without it `claude /usage` falls back
        // to the stored login, which can read quota.
        assertEquals(listOf("CLAUDE_CODE_OAUTH_TOKEN"), call("cli").environment.unset)
        assertEquals(listOf("CLAUDE_CODE_OAUTH_TOKEN"), call("cliCost").environment.unset)
    }

    // Completion Rule Pairing (issue #317)

    @Test
    fun `should wait for the usage screen before reading it (#317)`() {
        // The numbers or an error — never the `Current session` label, which Claude Code paints
        // before a second request fills its bars in.
        assertEquals(
            listOf(
                CLICall.ReadyMarker("% used"),
                CLICall.ReadyMarker("% left"),
                CLICall.ReadyMarker("rate limited"),
                CLICall.ReadyMarker("Error:"),
                CLICall.ReadyMarker("/usage is only available"),
            ),
            call("cli").readyWhen,
        )
    }

    /** Claude Code 2.1.289's `/usage`: the session's cost and the plugin footprint first, then the limits, whose numbers a second request fills in. */
    private val usageScreenBeforeTheNumbers = """
        Settings  Status  Config  Usage  Stats

        Session

        Total cost:            ${'$'}0.0000
        Total duration (API):  0s
        Usage:                 0 input, 0 output, 0 cache read, 0 cache write

        Plugin skill-listing footprint
        feature-dev                 1 skill · ~26 tok/turn

        Current session
        ████████████████████████████████████████
    """.trimIndent()

    private fun completionRule() = CLICompletionRule(call("cli").readyWhen.map { CLICompletionRule.Marker(it.text, endsRow = it.endsRow) })

    @Test
    fun `should keep waiting while the usage screen shows the session label but not its numbers yet`() {
        val rule = completionRule()

        assertTrue(rule.isPending(usageScreenBeforeTheNumbers))
        assertFalse(rule.isPending(usageScreenBeforeTheNumbers + "  37% used\nResets 3:59pm (Asia/Shanghai)\n"))
    }

    @Test
    fun `should let the cost screen end when the CLI goes idle, not wait for quota bars (#317)`() {
        // The regression #317 introduced: `/cost` shared the `/usage` rule, whose markers are
        // quota-bar markers. An API-billed account never paints a quota bar, so every `/cost`
        // capture burned the full 20s timeout. A rule must be "markers this screen can actually reach".
        assertFalse(call("cli").readyWhen.isEmpty())
        assertTrue(call("cliCost").readyWhen.isEmpty())
    }

    // Working directory

    @Test
    fun `should run both commands in ClaudeBar's dedicated folder`() {
        assertEquals(WorkingDirectory.DEDICATED, call("cli").workingDirectory)
        assertEquals(WorkingDirectory.DEDICATED, call("cliCost").workingDirectory)
    }

    // One shared probe session (issue #132)

    @Test
    fun `should run both commands in one named ClaudeBar session, the same id every time (#132)`() {
        val usage = call("cli").session
        val cost = call("cliCost").session

        // The session contract is the same on both — only the vendor's facts. The id is stable:
        // one per login, created each run, resumed only when a CLI that kept the session says it
        // is already in use.
        for (session in listOf(usage, cost)) {
            assertNotNull(session)
            assertEquals(CLICall.Session.Id("ClaudeBar Probe"), session!!.id)
            assertEquals(listOf("already in use"), session.resumeOn)
            assertEquals(listOf("--session-id", "{{id}}", "--name", "ClaudeBar Probe"), session.create)
            assertEquals(listOf("--resume", "{{id}}"), session.resume)
            assertEquals(listOf("no conversation found", "no session found"), session.recreateOn)
            assertTrue("unknown option '--session-id'" in session.unsupportedOn)
            assertTrue("unknown option '--resume'" in session.unsupportedOn)
            assertTrue(session.unsupportedOn.all { it.startsWith("unknown option") || it.startsWith("unexpected argument") })
        }
        assertEquals(usage, cost)
    }

    @Test
    fun `should create the dedicated folder under ClaudeBar's application support`() {
        val support = Files.createTempDirectory("application-support").toFile()
        try {
            val path = CLIWorkingDirectory.resolve(FakeMachine(applicationSupportDirectory = support.path), DiskFiles)

            assertTrue(path.contains("ClaudeBar/Probe"))
            assertTrue(File(path).exists())
        } finally {
            support.deleteRecursively()
        }
    }

    // Availability

    @Test
    fun `should be available when the Claude CLI is found`() {
        claude.cli.located = { "/usr/local/bin/claude" }
        val provider = claude.provider()

        assertTrue(provider.isPlainAvailable())
    }

    @Test
    fun `should be unavailable without the Claude CLI or an API login`() {
        claude.cli.located = { null }
        val provider = claude.provider()

        assertFalse(provider.isPlainAvailable())
    }

    // What a probe run gives

    @Test
    fun `should show the Max plan, both windows and the weekly reset from the usage screen`() {
        val snapshot = claude.readRawUsageScreen("""
            Opus 4.5 · Claude Max · user@example.com's Organization

            Current session
            ████████████████░░░░ 65% left
            Resets in 2h 15m

            Current week (all models)
            ██████████░░░░░░░░░░ 35% left
            Resets Dec 28
        """.trimIndent())

        assertEquals(AccountTier.ClaudeMax, snapshot.accountTier)
        assertEquals(2, snapshot.quotas.size)
        assertNotNull(snapshot.weeklyQuota?.resetsAtSeconds)
    }

    @Test
    fun `should show the Pro plan with its extra usage, $5_41 of $20, from the usage screen`() {
        val snapshot = claude.readRawUsageScreen("""
            Opus 4.5 · Claude Pro · user@example.com's Organization

            Current session
            █████░░░░░░░░░░░░░░░ 1% used
            Resets 4:59pm (America/New_York)

            Current week (all models)
            █████████████████░░░ 36% used
            Resets Dec 25 at 2:59pm (America/New_York)

            Extra usage
            █████░░░░░░░░░░░░░░░ 27% used
            ${'$'}5.41 / ${'$'}20.00 spent · Resets Jan 1, 2026 (America/New_York)
        """.trimIndent())

        assertEquals(AccountTier.ClaudePro, snapshot.accountTier)
        assertEquals(dollars("5.41"), snapshot.costUsage?.totalCostNanos)
        assertEquals(dollars("20.00"), snapshot.costUsage?.budgetNanos)
        assertEquals(CostUsage.Kind.EXTRA_USAGE, snapshot.costUsage?.kind)
        assertEquals(2, snapshot.quotas.size)
    }

    @Test
    fun `should show the email and organization from Claude's config when the usage screen has none`() {
        // new tabbed CLI output (no account info in the /usage tab)
        claude.writeClaudeConfig(email = "user@example.com", displayName = "testuser")

        val snapshot = claude.readRawUsageScreen("""
              Status   Config   Usage

            Current session
            ▌                                                  1% used
            Resets 12am (Asia/Shanghai)

            Current week (all models)
            ██████████████████████▌                            45% used
            Resets 10:59am (Asia/Shanghai)

            Extra usage
            Extra usage not enabled • /extra-usage to enable

            Esc to cancel
        """.trimIndent())

        // account info from config, tier from CLI output
        assertEquals("user@example.com", snapshot.accountEmail)
        assertEquals("testuser", snapshot.accountOrganization)
        assertTrue(snapshot.quotas.isNotEmpty())
        assertEquals(99.0, snapshot.sessionQuota?.percentRemaining)
    }

    // When /cost may answer (issues #271, #317)

    private val apiBillingPanel = """
        Opus 5 (1M context) · API Usage Billing

          Session
            Total cost:            ${'$'}0.0000
            Total duration (API):  0s
            Usage:                 0 input, 0 output, 0 cache read, 0 cache write
    """.trimIndent()

    private val apiUsage = """{"five_hour":{"utilization":45,"resets_at":"2099-01-01T00:00:00Z"}}"""

    private val subscriptionMisread =
        "The Claude CLI did not see this account's subscription — its usage screen reported API billing instead of a plan. " +
            "Run `claude auth login` again, or switch Claude to API mode in Settings."

    private fun answerScreens(usage: String, cost: String? = null) {
        claude.cli.located = { "/usr/local/bin/claude" }
        claude.cli.answer = { run -> CLIResult(if ("/cost" in run) cost ?: usage else usage, 0) }
    }

    @Test
    fun `should show the cost when the usage screen shows API billing for a pay-as-you-go account (#271)`() {
        // issue #271: the Usage tab paints a cost panel with no quota bars. A genuine pay-as-you-go
        // account — nothing in the config claims a subscription — so /cost answers it.
        claude.writeClaudeConfig(email = "user@example.com", billingType = "api")
        answerScreens(apiBillingPanel, cost = """
            Total cost:            ${'$'}1.25
            Total duration (API):  6m 19.7s
            Total duration (wall): 1h 2m
        """.trimIndent())
        val provider = claude.provider()

        val snapshot = provider.refreshPlain().usage()

        assertEquals(dollars("1.25"), snapshot.costUsage?.totalCostNanos)
        assertEquals(AccountTier.ClaudeApi, snapshot.accountTier)
        assertEquals("cliCost", provider.defaultAccount.answeredBy)
    }

    @Test
    fun `should fail rather than show a cost when the CLI misses a subscription the config claims (#271)`() {
        // issue #271: a Max plan billed through Apple renders the same cost panel, but the config
        // still says it is a subscription. With no API login either, the CLI's reason is reported.
        claude.writeClaudeConfig(email = "user@example.com", billingType = "apple_subscription")
        answerScreens(apiBillingPanel)
        val provider = claude.provider()

        assertEquals(RefreshOutcome.Failed(UsageError.ExecutionFailed(subscriptionMisread)), provider.refreshPlain())
        assertNull(provider.defaultAccount.snapshot)
    }

    @Test
    fun `should show the usage API's quotas when the CLI misses the subscription`() {
        claude.writeClaudeConfig(email = "user@example.com", billingType = "apple_subscription")
        answerScreens(apiBillingPanel)
        claude.writeCredentials(subscriptionType = "claude_max")
        claude.answer { claudeResponse(200, body = apiUsage) }
        val provider = claude.provider()

        val snapshot = provider.refreshPlain().usage()

        assertEquals("api", provider.defaultAccount.answeredBy)
        assertEquals(55.0, snapshot.sessionQuota?.percentRemaining)
        assertNull(snapshot.costUsage)
    }

    // Folder trust recovery

    private val trustPrompt = """
        Do you trust the files in this folder?
        /Users/test/project

        Yes, proceed (y)
        No, cancel (n)
    """.trimIndent()

    private val usageScreen = """
        Current session
        ████████████████░░░░ 65% left
        Resets in 2h 15m
    """.trimIndent()

    /** The first `/usage` shows the trust prompt, every later one the usage. */
    private fun answerTrustPromptOnce() {
        val runs = AtomicInteger()
        claude.cli.answer = { CLIResult(if (runs.incrementAndGet() == 1) trustPrompt else usageScreen, 0) }
    }

    private fun trust(config: JsonObject): Boolean? {
        val entry = (config["projects"] as? JsonObject)?.get(claude.cliDirectory) as? JsonObject
        return (entry?.get("hasTrustDialogAccepted") as? JsonPrimitive)?.boolean
    }

    @Test
    fun `should trust ClaudeBar's folder, keep the rest of the config and show the usage when the CLI asks`() {
        claude.writeClaudeConfig(email = "user@example.com", extra = mapOf("numStartups" to JsonPrimitive(3)))
        answerTrustPromptOnce()

        val snapshot = claude.fetchUsage(claude.dataSource("cli"))

        assertEquals(65.0, snapshot.sessionQuota?.percentRemaining)
        val config = claude.readClaudeConfig()
        assertEquals(true, trust(config))
        // The rest of the file is kept.
        assertEquals(3, (config["numStartups"] as JsonPrimitive).int)
        assertEquals("user@example.com", ((config["oauthAccount"] as JsonObject)["emailAddress"] as JsonPrimitive).content)
    }

    @Test
    fun `should keep the other trusted projects when ClaudeBar's folder is trusted`() {
        val trusted = JsonObject(mapOf("hasTrustDialogAccepted" to JsonPrimitive(true)))
        claude.writeClaudeConfig(extra = mapOf("projects" to JsonObject(mapOf("/Users/test/project" to trusted))))
        answerTrustPromptOnce()

        claude.fetchUsage(claude.dataSource("cli"))

        val projects = claude.readClaudeConfig()["projects"] as JsonObject
        assertEquals(true, ((projects["/Users/test/project"] as JsonObject)["hasTrustDialogAccepted"] as JsonPrimitive).boolean)
        assertEquals(true, trust(claude.readClaudeConfig()))
    }

    @Test
    fun `should report folder trust as needed, creating no config, when Claude has no config file`() {
        answerTrustPromptOnce()

        assertEquals(UsageError.FolderTrustRequired, claude.failure(claude.dataSource("cli")))
        assertFalse(File(claude.home, ".claude.json").exists())
    }

    @Test
    fun `should report folder trust as needed, not retry forever, when the folder is already trusted`() {
        val trusted = JsonObject(mapOf("hasTrustDialogAccepted" to JsonPrimitive(true)))
        claude.writeClaudeConfig(extra = mapOf("projects" to JsonObject(mapOf(claude.cliDirectory to trusted))))
        claude.cli.answer = { CLIResult(trustPrompt, 0) }

        assertEquals(UsageError.FolderTrustRequired, claude.failure(claude.dataSource("cli")))
    }

    @Test
    fun `should leave a config alone and report folder trust as needed when its projects are not an object`() {
        claude.writeClaudeConfig(extra = mapOf("projects" to JsonPrimitive("unexpected")))
        answerTrustPromptOnce()

        assertEquals(UsageError.FolderTrustRequired, claude.failure(claude.dataSource("cli")))
        assertEquals("unexpected", (claude.readClaudeConfig()["projects"] as JsonPrimitive).content)
    }

    // A user-configured CLI binary (#210)

    @Test
    fun `should run every Claude command from the CLI location the person chose, with everything else untouched (#210)`() {
        val definition = TestDefinitions.builtIn("claude").runningCLI("/opt/tools/bin/claude-work")

        assertEquals("/opt/tools/bin/claude-work", call("cli", definition).cli)
        assertEquals("/opt/tools/bin/claude-work", call("cliCost", definition).cli)
        assertEquals(listOf("/usage", "--allowed-tools", ""), call("cli", definition).args)
        assertEquals(listOf("/cost", "--allowed-tools", ""), call("cliCost", definition).args)
        assertEquals(20.0, call("cli", definition).timeout)
        assertEquals(CLICall.Screen.RENDERED, call("cli", definition).screen)
        assertEquals(call("cli").autoResponses, call("cli", definition).autoResponses)
        definition.validate()
    }

    @Test
    fun `should keep asking the usage API, never the chosen CLI, for the API data source`() {
        val definition = TestDefinitions.builtIn("claude").runningCLI("/opt/tools/bin/claude-work")
        val fetch = definition.dataSource("api")?.fetch

        assertTrue(fetch is Fetch.Http, "api is not an HTTP data source")
        assertEquals("https://api.anthropic.com/api/oauth/usage", (fetch as Fetch.Http).request.url)
    }

    @Test
    fun `should run Codex's RPC, terminal and sign-in from the chosen CLI location`() {
        val definition = TestDefinitions.builtIn("codex").runningCLI("/opt/tools/bin/codex-work")

        val rpc = (definition.dataSource("rpc")?.fetch as? Fetch.JsonRpc)?.call
        val tty = (definition.dataSource("tty")?.fetch as? Fetch.Cli)?.call
        assertNotNull(rpc, "codex lost its rpc data source")
        assertNotNull(tty, "codex lost its terminal data source")
        assertEquals("/opt/tools/bin/codex-work", rpc!!.cli)
        assertEquals("/opt/tools/bin/codex-work", tty!!.cli)
        assertEquals("/opt/tools/bin/codex-work", definition.accounts?.signIn?.cli)
        assertEquals(TestDefinitions.builtIn("codex").accounts?.signIn?.args, definition.accounts?.signIn?.args)
    }

    @Test
    fun `should sign in to Claude with the CLI at the chosen location`() {
        val definition = TestDefinitions.builtIn("claude").runningCLI("/opt/tools/bin/claude-work")

        assertEquals("/opt/tools/bin/claude-work", definition.accounts?.signIn?.cli)
    }

    @Test
    fun `should change nothing when the chosen location is empty, blank or the usual name`() {
        val claude = TestDefinitions.builtIn("claude")
        assertEquals(claude, claude.runningCLI(""))
        assertEquals(claude, claude.runningCLI("   \n "))
        assertEquals(claude, claude.runningCLI("claude"))
    }

    @Test
    fun `should change nothing for a provider without a CLI`() {
        val definition = ProviderDefinition.parse("""
            {
              "profile": { "id": "gemini", "name": "Gemini" },
              "enabledByDefault": true,
              "defaultDataSource": "api",
              "dataSources": [
                {
                  "kind": "api",
                  "fetch": { "http": { "url": "https://example.com/usage" } },
                  "mapping": { "json": { "quotas": [] } }
                }
              ]
            }
        """)
        assertEquals(definition, definition.runningCLI("/opt/tools/bin/gemini-work"))
    }

    @Test
    fun `should run an RPC data source from the chosen CLI location too`() {
        val definition = ProviderDefinition.parse("""
            {
              "profile": { "id": "codex", "name": "Codex" },
              "cli": "codex",
              "enabledByDefault": true,
              "defaultDataSource": "rpc",
              "dataSources": [
                {
                  "kind": "rpc",
                  "fetch": { "jsonRpc": { "cli": "codex", "args": ["app-server"], "call": "account/rateLimits/read" } },
                  "mapping": { "json": { "quotas": [] } }
                }
              ]
            }
        """)

        val call = (definition.runningCLI("/opt/tools/bin/codex-work").dataSource("rpc")?.fetch as? Fetch.JsonRpc)?.call
        assertNotNull(call, "rpc is not a JSON-RPC data source")
        assertEquals("/opt/tools/bin/codex-work", call!!.cli)
        assertEquals(listOf("app-server"), call.args)
        assertEquals("account/rateLimits/read", call.call)
    }
}
