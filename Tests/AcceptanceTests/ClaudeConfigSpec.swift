import Testing
import Foundation
import Mockable
import DataSources
import Providers
@testable import Domain
@testable import Infrastructure

/// Feature: Claude Configuration
///
/// Users switch Claude between CLI and API probe modes.
/// API mode uses OAuth credentials for direct HTTP calls.
///
/// Claude is a definition (`claude.json`) run by the one `Provider`; these
/// scenarios run that real definition, its mapping scripts and the Claude
/// card's settings keys over a stubbed terminal, network and home folder.
///
/// Behaviors covered:
/// - #28: User switches Claude to API mode → uses OAuth HTTP API instead of CLI
/// - #29: API mode shows credential status (found / not found)
/// - #30: Expired session shows user-friendly error message
@Suite("Feature: Claude Configuration")
struct ClaudeConfigSpec {

    struct TestClock: Clock {
        func sleep(for duration: Duration) async throws {}
        func sleep(nanoseconds: UInt64) async throws {}
    }

    static let usageScreen = """
    Current session
    ████████████████░░░░ 80% left
    Resets in 2h 15m
    """

    static let apiUsage = #"{"five_hour":{"utilization":55}}"#

    /// A fresh home folder, isolated settings, a stubbed terminal and network.
    final class World {
        let home: URL
        let settings: UserDefaultsProviderSettingsRepository
        let cli = MockCLIExecutor()
        let network = MockNetworkClient()

        init() throws {
            home = FileManager.default.temporaryDirectory.appendingPathComponent("claude-spec-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            settings = UserDefaultsProviderSettingsRepository(userDefaults: UserDefaults(suiteName: "com.claudebar.test.\(UUID().uuidString)")!)
            settings.setEnabled(true, forProvider: "claude")
        }

        deinit { try? FileManager.default.removeItem(at: home) }

        @MainActor
        func claude() throws -> Account {
            let definition = try Providers.builtIn("claude")
            let home = self.home
            let cli = self.cli
            let network = self.network
            return Provider(
                definition: definition,
                settings: settings,
                makeDataSource: {
                    DataSources.make(
                        $0,
                        providerId: "claude",
                        cliExecutor: cli,
                        network: network,
                        makeTransport: { _, _, _, _ in MockRPCTransport() },
                        scripts: Providers.builtInScripts,
                        environment: { _ in nil },
                        homeDirectory: home,
                        now: { Date() }
                    )
                }
            ).defaultAccount
        }

        func cliAnswers(_ screen: String) {
            given(cli).locate(.any).willReturn("/usr/local/bin/claude")
            given(cli).execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
                .willReturn(CLIResult(output: screen))
        }

        func apiAnswers(_ body: String, status: Int = 200) {
            given(network).request(.any).willReturn((
                Data(body.utf8),
                HTTPURLResponse(url: URL(string: "https://api.anthropic.com")!, statusCode: status, httpVersion: nil, headerFields: nil)!
            ))
        }

        /// `~/.claude.json`'s account, as Claude Code keeps it.
        func account(email: String, organization: String? = nil) throws {
            var account: [String: Any] = ["emailAddress": email]
            if let organization { account["displayName"] = organization }
            try JSONSerialization.data(withJSONObject: ["oauthAccount": account])
                .write(to: home.appendingPathComponent(".claude.json"))
        }

        /// `~/.claude/.credentials.json`, as `claude login` leaves it.
        func loggedIn() throws {
            let directory = home.appendingPathComponent(".claude")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let oauth: [String: Any] = [
                "accessToken": "token",
                "refreshToken": "refresh",
                "expiresAt": Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000,
                "subscriptionType": "claude_max",
            ]
            try JSONSerialization.data(withJSONObject: ["claudeAiOauth": oauth])
                .write(to: directory.appendingPathComponent(".credentials.json"))
        }
    }

    // MARK: - #28: Switch Claude to API mode

    @Suite("Scenario: Switch probe mode")
    @MainActor
    struct SwitchProbeMode {

        @Test
        func `switching to API mode uses the API for refresh`() async throws {
            // Given — the CLI says 80% left, the API 45% left
            let world = try World()
            world.cliAnswers(ClaudeConfigSpec.usageScreen)
            world.apiAnswers(ClaudeConfigSpec.apiUsage)
            try world.loggedIn()
            let claude = try world.claude()
            #expect(claude.provider.activeKind == "cli")

            // When — the Claude card saves API mode
            world.settings.setClaudeProbeMode(.api)
            let monitor = QuotaMonitor(providers: AIProviders(providers: [claude]), clock: ClaudeConfigSpec.TestClock())
            await monitor.refresh(providerId: "claude")

            // Then — the API's answer is shown
            #expect(claude.provider.activeKind == "api")
            #expect(claude.snapshot?.quotas.first?.percentRemaining == 45)
        }

        @Test
        func `probe mode is persisted in UserDefaults`() {
            let settings = UserDefaultsProviderSettingsRepository(userDefaults: UserDefaults(suiteName: "com.claudebar.test.\(UUID().uuidString)")!)
            #expect(settings.claudeProbeMode() == .cli)

            settings.setClaudeProbeMode(.api)

            #expect(settings.claudeProbeMode() == .api)
            #expect(settings.dataSourceKind(forProvider: "claude") == "api")
        }

        @Test
        func `api mode falls back to CLI when OAuth API is unavailable`() async throws {
            // Given — API mode, nobody logged in, the CLI works
            let world = try World()
            world.cliAnswers(ClaudeConfigSpec.usageScreen)
            world.settings.setClaudeProbeMode(.api)
            let claude = try world.claude()
            let monitor = QuotaMonitor(providers: AIProviders(providers: [claude]), clock: ClaudeConfigSpec.TestClock())

            // When
            await monitor.refresh(providerId: "claude")

            // Then — the CLI answered
            #expect(claude.snapshot?.quotas.first?.percentRemaining == 80)
            #expect(claude.answeredBy == "cli")
        }

        @Test
        func `api mode does not fall back to CLI when cli fallback is disabled`() async throws {
            // Given — API mode with the card's "CLI fallback" off
            let world = try World()
            world.cliAnswers(ClaudeConfigSpec.usageScreen)
            world.settings.setClaudeProbeMode(.api)
            world.settings.setClaudeCliFallbackEnabled(false)
            let claude = try world.claude()

            // Then — nothing is available, and a refresh reports the API's failure
            #expect(await claude.isAvailable() == false)
            await #expect(throws: UsageError.authenticationRequired) { try await claude.refresh() }
            #expect(claude.snapshot == nil)
        }

        @Test
        func `cli mode falls back to API when CLI parsing fails and OAuth is available`() async throws {
            // Given — the CLI screen has no usage, the API answers
            let world = try World()
            world.cliAnswers("Claude Code v2.1.0\nSomething unexpected")
            world.apiAnswers(ClaudeConfigSpec.apiUsage)
            try world.loggedIn()
            let claude = try world.claude()
            let monitor = QuotaMonitor(providers: AIProviders(providers: [claude]), clock: ClaudeConfigSpec.TestClock())

            // When
            await monitor.refresh(providerId: "claude")

            // Then
            #expect(claude.snapshot?.quotas.first?.percentRemaining == 45)
            #expect(claude.answeredBy == "api")
            #expect(claude.lastError == nil)
        }
    }

    // MARK: - #29: API mode credential availability

    @Suite("Scenario: API mode credential availability")
    @MainActor
    struct CredentialStatus {

        @Test
        func `OAuth credentials are found once claude has logged in`() throws {
            let world = try World()
            let claude = try world.claude()

            #expect(claude.hasKey(for: "api") == false)

            try world.loggedIn()

            #expect(claude.hasKey(for: "api") == true)
        }
    }

    // MARK: - #30: Expired session error

    @Suite("Scenario: Expired session shows user-friendly error")
    @MainActor
    struct SessionExpired {

        @Test
        func `sessionExpired error has user-friendly description`() async throws {
            // Given — API mode, the token is refused and so is its refresh
            let world = try World()
            world.settings.setClaudeProbeMode(.api)
            world.settings.setClaudeCliFallbackEnabled(false)
            world.apiAnswers("", status: 401)
            try world.loggedIn()
            let claude = try world.claude()
            let monitor = QuotaMonitor(providers: AIProviders(providers: [claude]), clock: ClaudeConfigSpec.TestClock())

            // When
            await monitor.refresh(providerId: "claude")

            // Then — user sees actionable error with provider-specific hint
            let description = claude.lastError?.localizedDescription ?? ""
            #expect(description.contains("Session expired"))
            #expect(description.contains("claude"))
        }
    }
}
