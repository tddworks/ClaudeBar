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
    func `claude is identified and enabled by default`() throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        let provider = try claude.provider()

        #expect(provider.id == "claude")
        #expect(provider.name == "Claude")
        #expect(provider.cliCommand == "claude")
        #expect(provider.dashboardURL == URL(string: "https://claude.ai/new#settings/usage"))
        #expect(provider.statusPageURL == URL(string: "https://status.anthropic.com"))
        #expect(provider.isEnabled)
        #expect(provider.provider.activeKind == "cli")
        #expect(provider.snapshot == nil)
        #expect(provider.lastError == nil)
    }

    // MARK: - CLI mode

    @Test
    func `cli mode reads the usage screen`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        answerCLI(claude, Self.usageScreen)
        let provider = try claude.provider()

        let usage = try await provider.refresh()

        #expect(usage.sessionQuota?.percentRemaining == 65)
        #expect(provider.answeredBy == "cli")
        #expect(provider.isSyncing == false)
    }

    @Test
    func `cli mode falls back to the api when the cli fails`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        failCLI(claude)
        try answerAPI(claude)
        let provider = try claude.provider()

        let usage = try await provider.refresh()

        #expect(usage.sessionQuota?.percentRemaining == 55)
        #expect(provider.answeredBy == "api")
        #expect(provider.lastError == nil)
    }

    @Test
    func `when the cli and the api both fail the cli failure is reported`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        failCLI(claude, .executionFailed("claude is not running"))
        try answerAPI(claude, "", status: 500)
        let provider = try claude.provider()

        await #expect(throws: UsageError.executionFailed("claude is not running")) { try await provider.refresh() }
        #expect(provider.lastError as? UsageError == .executionFailed("claude is not running"))
    }

    @Test
    func `an api billed account hands off to cost before the api`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        given(claude.cli).locate(.any).willReturn("/usr/local/bin/claude")
        given(claude.cli).execute(binary: .any, args: .matching { @Sendable args in args.first == "/usage" }, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willReturn(CLIResult(output: "/usage is only available for subscription plans."))
        given(claude.cli).execute(binary: .any, args: .matching { @Sendable args in args.first == "/cost" }, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willReturn(CLIResult(output: "Total cost:            $1.23\nTotal duration (API):  1m 30s"))
        let provider = try claude.provider()

        let usage = try await provider.refresh()

        #expect(provider.answeredBy == "cliCost")
        #expect(usage.accountTier == .claudeApi)
        #expect(usage.costUsage?.totalCost == Decimal(string: "1.23"))
        #expect(usage.costUsage?.apiDuration == 90)
    }

    // MARK: - API mode

    @Test
    func `api mode falls back to the cli unless the setting turns it off`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        answerCLI(claude, Self.usageScreen)
        let allowed = InMemoryProviderSettings(dataSourceKinds: ["claude": "api"])
        let refused = InMemoryProviderSettings(dataSourceKinds: ["claude": "api"], flags: ["claude.cliFallbackEnabled": false])

        // No credentials: the api cannot answer.
        let withFallback = try claude.provider(settings: allowed)
        let withoutFallback = try claude.provider(settings: refused)

        #expect(await withFallback.isAvailable())
        #expect(await withoutFallback.isAvailable() == false)
        #expect(try await withFallback.refresh().sessionQuota?.percentRemaining == 65)
        await #expect(throws: UsageError.authenticationRequired) { try await withoutFallback.refresh() }
    }

    @Test
    func `a rate limited api does not fall back to the cli`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        answerCLI(claude, Self.usageScreen)
        try answerAPI(claude, "", status: 429, headers: ["Retry-After": "120"])
        let provider = try claude.provider(settings: InMemoryProviderSettings(dataSourceKinds: ["claude": "api"]))

        await #expect(throws: UsageError.self) { try await provider.refresh() }

        guard case .rateLimited? = provider.lastError as? UsageError else {
            Issue.record("expected rateLimited, got \(String(describing: provider.lastError))")
            return
        }
        #expect(provider.snapshot == nil)
    }

    @Test
    func `when the api and the cli both fail the api failure is reported`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        failCLI(claude)
        try answerAPI(claude, "", status: 500)
        let provider = try claude.provider(settings: InMemoryProviderSettings(dataSourceKinds: ["claude": "api"]))

        await #expect(throws: UsageError.executionFailed("HTTP error: 500")) { try await provider.refresh() }
    }

    @Test
    func `the api sets a fifteen minute background floor and the cli none`() throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }

        #expect(try claude.provider(settings: InMemoryProviderSettings(dataSourceKinds: ["claude": "api"])).backgroundRefreshFloor == .seconds(900))
        #expect(try claude.provider().backgroundRefreshFloor == nil)
    }

    // MARK: - Guest passes

    @Test
    func `guest passes are offered to max and not to pro or before a refresh`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        let passes = GuestPasses(source: MockGuestPassSource())

        #expect(passes.isOffered(for: nil) == false)
        #expect(passes.isOffered(for: UsageSnapshot(providerId: "claude", quotas: [], capturedAt: Date(), accountTier: .claudeMax)))
        #expect(passes.isOffered(for: UsageSnapshot(providerId: "claude", quotas: [], capturedAt: Date(), accountTier: .claudePro)) == false)
        #expect(passes.isOffered(for: UsageSnapshot(providerId: "claude", quotas: [], capturedAt: Date(), accountTier: .claudeApi)) == false)
    }

    @Test
    func `a fetched pass is kept`() async throws {
        let source = MockGuestPassSource()
        let pass = GuestPass(passesRemaining: 3, referralURL: URL(string: "https://claude.ai/referral/abc")!)
        given(source).fetch().willReturn(pass)
        let passes = GuestPasses(source: source)

        try await passes.fetch()

        #expect(passes.pass == pass)
        #expect(passes.error == nil)
        #expect(passes.isFetching == false)
    }

    @Test
    func `a failed pass fetch is kept apart from usage and can be dismissed`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        answerCLI(claude, Self.usageScreen)
        let source = MockGuestPassSource()
        given(source).fetch().willThrow(UsageError.parseFailed("Could not find referral URL"))
        let passes = GuestPasses(source: source)
        let provider = try claude.provider(guestPasses: passes)
        try await provider.refresh()

        await #expect(throws: UsageError.self) { try await passes.fetch() }

        #expect(passes.error != nil)
        #expect(provider.lastError == nil)
        #expect(provider.guestPasses === passes)
        passes.clearError()
        #expect(passes.error == nil)
    }
}
