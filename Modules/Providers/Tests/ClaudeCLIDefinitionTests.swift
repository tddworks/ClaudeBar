import DataSources
import Quotas
import Foundation
import Mockable
import Providers
import Testing
@testable import DataSources

/// How `claude.json` runs the Claude CLI — the `cli` (`/usage`) and `cliCost`
/// (`/cost`) data sources — and what the old `ClaudeUsageProbeTests` pinned
/// about a probe run: its environment, its completion rule, where it runs,
/// what its screens give, when `/cost` may answer, and folder-trust recovery.
@MainActor
@Suite
struct ClaudeCLIDefinitionTests {

    private func call(_ kind: String) throws -> CLICall {
        try call(kind, in: Providers.builtIn("claude"))
    }

    private func call(_ kind: String, in definition: ProviderDefinition) throws -> CLICall {
        guard case .cli(let call)? = definition.dataSource(kind)?.fetch else {
            Issue.record("\(kind) is not a CLI data source")
            throw UsageError.noData
        }
        return call
    }

    // MARK: - The commands

    @Test
    func `the cli data source runs usage and the cost data source runs cost`() throws {
        #expect(try call("cli").cli == "claude")
        #expect(try call("cli").args == ["/usage", "--allowed-tools", ""])
        #expect(try call("cliCost").cli == "claude")
        #expect(try call("cliCost").args == ["/cost", "--allowed-tools", ""])
        #expect(try call("cli").timeout == 20)
        #expect(try call("cliCost").timeout == 20)
    }

    @Test
    func `both commands answer the CLI's start-up prompts`() throws {
        let expected = [
            "Esc to cancel": "\r",
            "Ready to code here?": "\r",
            "Press Enter to continue": "\r",
            "ctrl+t to disable": "\r",
            "Yes, I trust this folder": "\r",
        ]
        #expect(try call("cli").autoResponses == expected)
        #expect(try call("cliCost").autoResponses == expected)
    }

    @Test
    func `both screens are drawn by the terminal emulator before reading`() throws {
        #expect(try call("cli").screen == .rendered)
        #expect(try call("cliCost").screen == .rendered)
    }

    // MARK: - Probe session marking (issue #222)

    @Test
    func `probe marks its claude sessions with the probe environment marker`() throws {
        #expect(try call("cli").environment.set["CLAUDEBAR_PROBE"] == "1")
        #expect(try call("cliCost").environment.set["CLAUDEBAR_PROBE"] == "1")
    }

    // MARK: - Setup Token Environment Exclusion

    @Test
    func `the probe strips CLAUDE_CODE_OAUTH_TOKEN and nothing else`() throws {
        // The setup-token has only `user:inference` scope; without it `claude /usage`
        // falls back to the stored login, which can read quota.
        #expect(try call("cli").environment.unset == ["CLAUDE_CODE_OAUTH_TOKEN"])
        #expect(try call("cliCost").environment.unset == ["CLAUDE_CODE_OAUTH_TOKEN"])
    }

    // MARK: - Completion Rule Pairing (issue #317)

    @Test
    func `usage waits for the usage screen`() throws {
        #expect(try call("cli").readyWhen == [
            CLICall.ReadyMarker("Current session", endsRow: true),
            CLICall.ReadyMarker("% used"),
            CLICall.ReadyMarker("% left"),
            CLICall.ReadyMarker("rate limited"),
            CLICall.ReadyMarker("Error:"),
            CLICall.ReadyMarker("/usage is only available"),
        ])
    }

    @Test
    func `the cost fallback runs with no completion rule so it ends on idle`() throws {
        // The regression #317 introduced: `/cost` shared the `/usage` rule, whose
        // markers are quota-bar markers. An API-billed account never paints a
        // quota bar, so every `/cost` capture burned the full 20s timeout instead
        // of the ~3.7s it takes with no rule. A rule must be "markers this screen
        // can actually reach".
        #expect(try call("cli").readyWhen.isEmpty == false)
        #expect(try call("cliCost").readyWhen.isEmpty)
    }

    // MARK: - Working directory

    @Test
    func `both commands run in the probe directory`() throws {
        #expect(try call("cli").workingDirectory == .dedicated)
        #expect(try call("cliCost").workingDirectory == .dedicated)
    }

    // MARK: - One shared probe session (issue #132)

    @Test
    func `both commands run inside a named probe session`() throws {
        let usage = try call("cli").session
        let cost = try call("cliCost").session

        // The session contract is the same on both — only the vendor's facts;
        // which session a login is in is the worker's own memory.
        for session in [usage, cost] {
            let session = try #require(session)
            #expect(session.create == ["--session-id", "{{id}}", "--name", "ClaudeBar Probe"])
            #expect(session.resume == ["--resume", "{{id}}"])
            #expect(session.recreateOn == ["no conversation found", "no session found"])
            #expect(session.unsupportedOn.contains("unknown option '--session-id'"))
            #expect(session.unsupportedOn.contains("unknown option '--resume'"))
            #expect(session.unsupportedOn.allSatisfy { $0.hasPrefix("unknown option") || $0.hasPrefix("unexpected argument") })
        }
        #expect(usage == cost)
    }

    @Test
    func `the probe directory is created under ClaudeBar's application support`() {
        let url = CLIWorkingDirectory.resolve()

        #expect(url.path.contains("ClaudeBar/Probe"))
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - Availability

    @Test
    func `claude is available when the CLI is found`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        given(claude.cli).locate(.any).willReturn("/usr/local/bin/claude")
        let provider = try claude.provider()

        #expect(await provider.isAvailable() == true)
    }

    @Test
    func `claude is unavailable without the CLI or an API login`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        given(claude.cli).locate(.any).willReturn(nil)
        let provider = try claude.provider()

        #expect(await provider.isAvailable() == false)
    }

    // MARK: - What a probe run gives

    @Test
    func `probe extracts account type from usage output`() throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }

        let snapshot = try claude.readRawUsageScreen("""
        Opus 4.5 · Claude Max · user@example.com's Organization

        Current session
        ████████████████░░░░ 65% left
        Resets in 2h 15m

        Current week (all models)
        ██████████░░░░░░░░░░ 35% left
        Resets Dec 28
        """)

        #expect(snapshot.accountTier == .claudeMax)
        #expect(snapshot.quotas.count == 2)
        #expect(snapshot.weeklyQuota?.resetsAt != nil)
    }

    @Test
    func `probe extracts Pro account with Extra usage`() throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }

        let snapshot = try claude.readRawUsageScreen("""
        Opus 4.5 · Claude Pro · user@example.com's Organization

        Current session
        █████░░░░░░░░░░░░░░░ 1% used
        Resets 4:59pm (America/New_York)

        Current week (all models)
        █████████████████░░░ 36% used
        Resets Dec 25 at 2:59pm (America/New_York)

        Extra usage
        █████░░░░░░░░░░░░░░░ 27% used
        $5.41 / $20.00 spent · Resets Jan 1, 2026 (America/New_York)
        """)

        #expect(snapshot.accountTier == .claudePro)
        #expect(snapshot.costUsage?.totalCost == Decimal(string: "5.41"))
        #expect(snapshot.costUsage?.budget == Decimal(string: "20.00"))
        #expect(snapshot.costUsage?.kind == .extraUsage)
        #expect(snapshot.quotas.count == 2)
    }

    @Test
    func `probe resolves account info from config file`() throws {
        // new tabbed CLI output (no account info in the /usage tab)
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try claude.writeClaudeConfig(email: "user@example.com", displayName: "testuser")

        let snapshot = try claude.readRawUsageScreen("""
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
        """)

        // account info from config, tier from CLI output
        #expect(snapshot.accountEmail == "user@example.com")
        #expect(snapshot.accountOrganization == "testuser")
        #expect(snapshot.quotas.count >= 1)
        #expect(snapshot.sessionQuota?.percentRemaining == 99)
    }

    // MARK: - When /cost may answer (issues #271, #317)

    static let apiBillingPanel = """
    Opus 5 (1M context) · API Usage Billing

      Session
        Total cost:            $0.0000
        Total duration (API):  0s
        Usage:                 0 input, 0 output, 0 cache read, 0 cache write
    """

    static let apiUsage = #"{"five_hour":{"utilization":45,"resets_at":"2099-01-01T00:00:00Z"}}"#

    static let subscriptionMisread =
        "The Claude CLI did not see this account's subscription — its usage screen reported API billing instead of a plan. "
        + "Run `claude login` again, or switch Claude to API mode in Settings."

    private func answerScreens(_ claude: ClaudeHarness, usage: String, cost: String? = nil) {
        given(claude.cli).locate(.any).willReturn("/usr/local/bin/claude")
        given(claude.cli).execute(binary: .any, args: .matching { @Sendable args in args.first == "/usage" }, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willReturn(CLIResult(output: usage, exitCode: 0))
        given(claude.cli).execute(binary: .any, args: .matching { @Sendable args in args.first == "/cost" }, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willReturn(CLIResult(output: cost ?? usage, exitCode: 0))
    }

    @Test
    func `probe falls back to cost when usage renders the API billing panel`() async throws {
        // issue #271: the Usage tab paints a cost panel with no quota bars. A
        // genuine pay-as-you-go account — nothing in the config claims a
        // subscription — so the cost panel is the truth and /cost answers it.
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try claude.writeClaudeConfig(email: "user@example.com", billingType: "api")
        answerScreens(claude, usage: Self.apiBillingPanel, cost: """
        Total cost:            $1.25
        Total duration (API):  6m 19.7s
        Total duration (wall): 1h 2m
        """)
        let provider = try claude.provider()

        let snapshot = try await provider.refresh()

        #expect(snapshot.costUsage?.totalCost == Decimal(string: "1.25"))
        #expect(snapshot.accountTier == .claudeApi)
        #expect(provider.answeredBy == "cliCost")
    }

    @Test
    func `probe fails instead of costing out a subscription the CLI could not see`() async throws {
        // issue #271: a Max plan billed through Apple renders the same cost
        // panel, but the config still says it is a subscription. /cost would
        // answer $0.00 with no quota, and its success would stop the usage API
        // from running. With no API login either, the CLI's reason is reported.
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try claude.writeClaudeConfig(email: "user@example.com", billingType: "apple_subscription")
        answerScreens(claude, usage: Self.apiBillingPanel)
        let provider = try claude.provider()

        await #expect(throws: UsageError.executionFailed(Self.subscriptionMisread)) {
            try await provider.refresh()
        }
        #expect(provider.snapshot == nil)
    }

    @Test
    func `a subscription the CLI could not see is read by the usage API instead`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try claude.writeClaudeConfig(email: "user@example.com", billingType: "apple_subscription")
        answerScreens(claude, usage: Self.apiBillingPanel)
        try claude.writeCredentials(subscriptionType: "claude_max")
        given(claude.network).request(.any).willReturn((Data(Self.apiUsage.utf8), ClaudeHarness.response(200)))
        let provider = try claude.provider()

        let snapshot = try await provider.refresh()

        #expect(provider.answeredBy == "api")
        #expect(snapshot.sessionQuota?.percentRemaining == 55)
        #expect(snapshot.costUsage == nil)
    }

    // MARK: - Folder trust recovery

    static let trustPrompt = """
    Do you trust the files in this folder?
    /Users/test/project

    Yes, proceed (y)
    No, cancel (n)
    """

    static let usageScreen = """
    Current session
    ████████████████░░░░ 65% left
    Resets in 2h 15m
    """

    /// The first `/usage` shows the trust prompt, every later one the usage.
    private func answerTrustPromptOnce(_ claude: ClaudeHarness) {
        let runs = Counter()
        let prompt = Self.trustPrompt
        let usage = Self.usageScreen
        given(claude.cli).execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willProduce { @Sendable _, _, _, _, _, _ in
                CLIResult(output: runs.next() == 1 ? prompt : usage, exitCode: 0)
            }
    }

    private func trust(in config: [String: Any]) -> Any? {
        let projects = config["projects"] as? [String: Any]
        let entry = projects?[CLIWorkingDirectory.resolve().path] as? [String: Any]
        return entry?["hasTrustDialogAccepted"]
    }

    @Test
    func `a trust prompt marks the probe directory trusted and reads again`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try claude.writeClaudeConfig(email: "user@example.com", extra: ["numStartups": 3])
        answerTrustPromptOnce(claude)

        let snapshot = try await claude.fetchUsage(claude.dataSource("cli"))

        #expect(snapshot.sessionQuota?.percentRemaining == 65)
        let config = try claude.readClaudeConfig()
        #expect(trust(in: config) as? Bool == true)
        // The rest of the file is kept.
        #expect(config["numStartups"] as? Int == 3)
        #expect((config["oauthAccount"] as? [String: Any])?["emailAddress"] as? String == "user@example.com")
    }

    @Test
    func `a trust prompt keeps the other projects in the config`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try claude.writeClaudeConfig(extra: ["projects": ["/Users/test/project": ["hasTrustDialogAccepted": true]]])
        answerTrustPromptOnce(claude)

        _ = try await claude.fetchUsage(claude.dataSource("cli"))

        let projects = try claude.readClaudeConfig()["projects"] as? [String: Any]
        #expect((projects?["/Users/test/project"] as? [String: Any])?["hasTrustDialogAccepted"] as? Bool == true)
        #expect(trust(in: try claude.readClaudeConfig()) as? Bool == true)
    }

    @Test
    func `a trust prompt without a config file is reported, and no file is created`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        answerTrustPromptOnce(claude)

        await #expect(throws: UsageError.folderTrustRequired) {
            try await claude.fetchUsage(claude.dataSource("cli"))
        }
        #expect(FileManager.default.fileExists(atPath: claude.home.appendingPathComponent(".claude.json").path) == false)
    }

    @Test
    func `a trust prompt for a directory already trusted is reported, not retried forever`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try claude.writeClaudeConfig(extra: ["projects": [CLIWorkingDirectory.resolve().path: ["hasTrustDialogAccepted": true]]])
        given(claude.cli).execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willReturn(CLIResult(output: Self.trustPrompt, exitCode: 0))

        await #expect(throws: UsageError.folderTrustRequired) {
            try await claude.fetchUsage(claude.dataSource("cli"))
        }
    }

    @Test
    func `a config whose projects is not an object is left alone`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try claude.writeClaudeConfig(extra: ["projects": "unexpected"])
        answerTrustPromptOnce(claude)

        await #expect(throws: UsageError.folderTrustRequired) {
            try await claude.fetchUsage(claude.dataSource("cli"))
        }
        #expect(try claude.readClaudeConfig()["projects"] as? String == "unexpected")
    }

    // MARK: - A user-configured CLI binary (#210)

    @Test
    func `a configured binary runs in every claude command, with everything else untouched`() throws {
        let definition = try Providers.builtIn("claude").runningCLI("/opt/tools/bin/claude-work")

        #expect(try call("cli", in: definition).cli == "/opt/tools/bin/claude-work")
        #expect(try call("cliCost", in: definition).cli == "/opt/tools/bin/claude-work")
        #expect(try call("cli", in: definition).args == ["/usage", "--allowed-tools", ""])
        #expect(try call("cliCost", in: definition).args == ["/cost", "--allowed-tools", ""])
        #expect(try call("cli", in: definition).timeout == 20)
        #expect(try call("cli", in: definition).screen == .rendered)
        let prompts = try call("cli").autoResponses
        #expect(try call("cli", in: definition).autoResponses == prompts)
        try definition.validate()
    }

    @Test
    func `the api data source never runs the binary`() throws {
        let definition = try Providers.builtIn("claude").runningCLI("/opt/tools/bin/claude-work")
        guard case .http(let request)? = definition.dataSource("api")?.fetch else {
            Issue.record("api is not an HTTP data source")
            throw UsageError.noData
        }
        #expect(request.url == "https://api.anthropic.com/api/oauth/usage")
    }

    @Test
    func `codex's rpc, terminal and sign-in all run the configured binary`() throws {
        let definition = try Providers.builtIn("codex").runningCLI("/opt/tools/bin/codex-work")

        guard case .jsonRpc(let rpc)? = definition.dataSource("rpc")?.fetch,
              case .cli(let tty)? = definition.dataSource("tty")?.fetch else {
            Issue.record("codex lost its rpc or terminal data source")
            throw UsageError.noData
        }
        #expect(rpc.cli == "/opt/tools/bin/codex-work")
        #expect(tty.cli == "/opt/tools/bin/codex-work")
        #expect(definition.accounts?.signIn?.cli == "/opt/tools/bin/codex-work")
        #expect(definition.accounts?.signIn?.args == (try Providers.builtIn("codex")).accounts?.signIn?.args)
    }

    @Test
    func `claude's sign-in runs the configured binary`() throws {
        let definition = try Providers.builtIn("claude").runningCLI("/opt/tools/bin/claude-work")

        #expect(definition.accounts?.signIn?.cli == "/opt/tools/bin/claude-work")
    }

    @Test
    func `an empty, blank or unchanged name is a no-op`() throws {
        let claude = try Providers.builtIn("claude")
        #expect(try claude.runningCLI("") == claude)
        #expect(try claude.runningCLI("   \n ") == claude)
        #expect(try claude.runningCLI("claude") == claude)
    }

    @Test
    func `a definition without a cli has nothing to re-point`() throws {
        let definition = try ProviderDefinition.parse(Data("""
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
        """.utf8))
        #expect(try definition.runningCLI("/opt/tools/bin/gemini-work") == definition)
    }

    @Test
    func `an rpc data source runs the configured binary too`() throws {
        let definition = try ProviderDefinition.parse(Data("""
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
        """.utf8))

        let rePointed = try definition.runningCLI("/opt/tools/bin/codex-work")
        guard case .jsonRpc(let call)? = rePointed.dataSource("rpc")?.fetch else {
            Issue.record("rpc is not a JSON-RPC data source")
            throw UsageError.noData
        }
        #expect(call.cli == "/opt/tools/bin/codex-work")
        #expect(call.args == ["app-server"])
        #expect(call.call == "account/rateLimits/read")
    }
}
