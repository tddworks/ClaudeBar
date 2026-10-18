import DataSources
import Quotas
import Foundation
import Mockable
import Providers
import Testing

/// Claude as a `Provider` built from `claude.json`: the lifecycle the old
/// `ClaudeProvider` tests pinned — which data source runs, when it hands
/// over, which failure is reported, the API's background floor, today's
/// usage on interactive refreshes only, and guest passes.
@MainActor
@Suite
struct ClaudeProviderTests {
    static let usageScreen = """
    Current session
    ████████████████░░░░ 65% left
    Resets in 2h 15m

    Current week (all models)
    ██████████░░░░░░░░░░ 35% left
    """

    static let apiUsage = #"{"five_hour":{"utilization":45,"resets_at":"2099-01-01T00:00:00Z"}}"#

    // MARK: - Helpers

    private func answerCLI(_ claude: ClaudeHarness, _ screen: String) {
        given(claude.cli).locate(.any).willReturn("/usr/local/bin/claude")
        given(claude.cli).execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willReturn(CLIResult(output: screen))
    }

    private func failCLI(_ claude: ClaudeHarness, _ error: UsageError = .executionFailed("claude is not running")) {
        given(claude.cli).locate(.any).willReturn("/usr/local/bin/claude")
        given(claude.cli).execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willThrow(error)
    }

    private func answerAPI(_ claude: ClaudeHarness, _ body: String = apiUsage, status: Int = 200, headers: [String: String] = [:]) throws {
        try claude.writeCredentials(subscriptionType: "claude_max")
        given(claude.network).request(.any).willReturn((Data(body.utf8), ClaudeHarness.response(status, headers)))
    }


    // MARK: - Identity

    @Test
    func `should be Claude, on by default, run from the CLI, with no usage or error yet`() throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        let provider = try claude.provider()

        #expect(provider.id == "claude")
        #expect(provider.lineupName(of: provider.defaultAccount) == "Claude")
        #expect(provider.defaultAccount.cliCommand == "claude")
        #expect(provider.plainDashboardURL == URL(string: "https://claude.ai/new#settings/usage"))
        #expect(provider.defaultAccount.statusPageURL == URL(string: "https://status.anthropic.com"))
        #expect(provider.isEnabled)
        #expect(provider.configuration.activeKind == "cli")
        #expect(provider.defaultAccount.snapshot == nil)
        #expect(provider.defaultAccount.lastError == nil)
    }

    // MARK: - CLI mode

    @Test(.needsTerminal)
    func `should show the usage screen when Claude reads from the CLI`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        answerCLI(claude, Self.usageScreen)
        let provider = try claude.provider()

        let usage = try await provider.refreshPlain()

        #expect(usage.sessionQuota?.percentRemaining == 65)
        #expect(provider.defaultAccount.answeredBy == "cli")
        #expect(provider.defaultAccount.isSyncing == false)
    }

    @Test
    func `should show the usage API's quotas when the CLI fails`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        failCLI(claude)
        try answerAPI(claude)
        let provider = try claude.provider()

        let usage = try await provider.refreshPlain()

        #expect(usage.sessionQuota?.percentRemaining == 55)
        #expect(provider.defaultAccount.answeredBy == "api")
        #expect(provider.defaultAccount.lastError == nil)
    }

    @Test(.needsTerminal)
    func `should report the CLI's failure when the CLI and the API both fail`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        failCLI(claude, .executionFailed("claude is not running"))
        try answerAPI(claude, "", status: 500)
        let provider = try claude.provider()

        await #expect(throws: UsageError.executionFailed("claude is not running")) { try await provider.refreshPlain() }
        #expect(provider.defaultAccount.lastError as? UsageError == .executionFailed("claude is not running"))
    }

    @Test(.needsTerminal)
    func `should show the cost screen before trying the API when the account is billed by API`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        given(claude.cli).locate(.any).willReturn("/usr/local/bin/claude")
        given(claude.cli).execute(binary: .any, args: .matching { @Sendable args in args.first == "/usage" }, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willReturn(CLIResult(output: "/usage is only available for subscription plans."))
        given(claude.cli).execute(binary: .any, args: .matching { @Sendable args in args.first == "/cost" }, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willReturn(CLIResult(output: "Total cost:            $1.23\nTotal duration (API):  1m 30s"))
        let provider = try claude.provider()

        let usage = try await provider.refreshPlain()

        #expect(provider.defaultAccount.answeredBy == "cliCost")
        #expect(usage.accountTier == .claudeApi)
        #expect(usage.costUsage?.totalCost == Decimal(string: "1.23"))
        #expect(usage.costUsage?.apiDuration == 90)
    }

    // MARK: - API mode

    @Test(.needsTerminal)
    func `should fall back from the API to the CLI unless the person turns the fallback off`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        answerCLI(claude, Self.usageScreen)
        let allowed = InMemoryProviderSettings(dataSourceKinds: ["claude": "api"])
        let refused = InMemoryProviderSettings(dataSourceKinds: ["claude": "api"], flags: ["claude.cliFallbackEnabled": false])

        // No credentials: the api cannot answer.
        let withFallback = try claude.provider(settings: allowed)
        let withoutFallback = try claude.provider(settings: refused)

        #expect(await withFallback.isPlainAvailable())
        #expect(await withoutFallback.isPlainAvailable() == false)
        #expect(try await withFallback.refreshPlain().sessionQuota?.percentRemaining == 65)
        await #expect(throws: UsageError.authenticationRequired) { try await withoutFallback.refreshPlain() }
    }

    @Test
    func `should report the rate limit and not fall back to the CLI when the API is rate-limited`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        answerCLI(claude, Self.usageScreen)
        try answerAPI(claude, "", status: 429, headers: ["Retry-After": "120"])
        let provider = try claude.provider(settings: InMemoryProviderSettings(dataSourceKinds: ["claude": "api"]))

        await #expect(throws: UsageError.self) { try await provider.refreshPlain() }

        guard case .rateLimited? = provider.defaultAccount.lastError as? UsageError else {
            Issue.record("expected rateLimited, got \(String(describing: provider.defaultAccount.lastError))")
            return
        }
        #expect(provider.defaultAccount.snapshot == nil)
    }

    @Test
    func `should report the API's failure when the API and the CLI both fail`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        failCLI(claude)
        try answerAPI(claude, "", status: 500)
        let provider = try claude.provider(settings: InMemoryProviderSettings(dataSourceKinds: ["claude": "api"]))

        await #expect(throws: UsageError.executionFailed("HTTP error: 500")) { try await provider.refreshPlain() }
    }

    @Test
    func `should refresh in the background no more than every fifteen minutes on the API, with no floor on the CLI`() throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }

        #expect(try claude.provider(settings: InMemoryProviderSettings(dataSourceKinds: ["claude": "api"])).backgroundRefreshFloor == .seconds(900))
        #expect(try claude.provider().backgroundRefreshFloor == nil)
    }

    // MARK: - Guest passes

    @Test
    func `should offer guest passes to Max, not to Pro or API, nor before a refresh`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        let passes = GuestPasses(source: MockGuestPassSource())

        #expect(passes.isOffered(for: nil) == false)
        #expect(passes.isOffered(for: UsageSnapshot(providerId: "claude", quotas: [], capturedAt: Date(), accountTier: .claudeMax)))
        #expect(passes.isOffered(for: UsageSnapshot(providerId: "claude", quotas: [], capturedAt: Date(), accountTier: .claudePro)) == false)
        #expect(passes.isOffered(for: UsageSnapshot(providerId: "claude", quotas: [], capturedAt: Date(), accountTier: .claudeApi)) == false)
    }

    @Test
    func `should keep a guest pass once it is fetched`() async throws {
        let source = MockGuestPassSource()
        let pass = GuestPass(passesRemaining: 3, referralURL: URL(string: "https://claude.ai/referral/abc")!)
        given(source).fetch().willReturn(pass)
        let passes = GuestPasses(source: source)

        try await passes.fetch()

        #expect(passes.pass == pass)
        #expect(passes.error == nil)
        #expect(passes.isFetching == false)
    }

    @Test(.needsTerminal)
    func `should keep a failed guest pass fetch apart from usage and let it be dismissed`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        answerCLI(claude, Self.usageScreen)
        let source = MockGuestPassSource()
        given(source).fetch().willThrow(UsageError.parseFailed("Could not find referral URL"))
        let passes = GuestPasses(source: source)
        let provider = try claude.provider(guestPasses: passes)
        try await provider.refreshPlain()

        await #expect(throws: UsageError.self) { try await passes.fetch() }

        #expect(passes.error != nil)
        #expect(provider.defaultAccount.lastError == nil)
        #expect(provider.defaultAccount.guestPasses === passes)
        passes.clearError()
        #expect(passes.error == nil)
    }
}
