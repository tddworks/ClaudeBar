import Testing
import Foundation
import Mockable
import DataSources
import Providers
@testable import Domain
@testable import Infrastructure

/// Feature: Codex Configuration
///
/// Users switch Codex between RPC and API probe modes.
/// API mode uses OAuth credentials from ~/.codex/auth.json.
///
/// Codex is a definition (`codex.json`) run by the one `Provider`; these
/// scenarios run that real definition over stubbed connections.
///
/// Behaviors covered:
/// - #33: User switches Codex to API mode → uses ChatGPT backend API instead of RPC
/// - #34: API mode shows credential status (found / not found)
@Suite("Feature: Codex Configuration")
struct CodexConfigSpec {

    private struct TestClock: Clock {
        func sleep(for duration: Duration) async throws {}
        func sleep(nanoseconds: UInt64) async throws {}
    }

    /// Codex from its definition, with a stubbed network and app-server and
    /// `~` pointing at a fresh temporary folder.
    @MainActor
    private static func makeCodex(
        settings: any MultiAccountSettingsRepository,
        home: URL,
        network: MockNetworkClient = MockNetworkClient(),
        transport: MockRPCTransport = MockRPCTransport()
    ) throws -> Account {
        let definition = try Providers.builtIn("codex")
        return Provider(
            definition: definition,
            settings: settings,
            makeDataSource: {
                DataSources.make(
                    $0,
                    providerId: "codex",
                    cliExecutor: MockCLIExecutor(),
                    network: network,
                    makeTransport: { _, _, _, _ in transport },
                    environment: { _ in nil },
                    homeDirectory: home,
                    now: { Date() }
                )
            }
        ).defaultAccount
    }

    private static func makeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("codex-spec-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private static func writeAuth(in home: URL) throws {
        let directory = home.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let auth: [String: Any] = [
            "tokens": ["access_token": "token", "refresh_token": "refresh"],
            "last_refresh": ISO8601DateFormatter().string(from: Date()),
        ]
        try JSONSerialization.data(withJSONObject: auth).write(to: directory.appendingPathComponent("auth.json"))
    }

    // MARK: - #33: Switch Codex to API mode

    @Suite("Scenario: Switch probe mode")
    @MainActor
    struct SwitchProbeMode {

        @Test
        func `switching to API mode uses the API for refresh`() async throws {
            // Given — isolated settings, credentials, and both endpoints answering
            let settings = UserDefaultsProviderSettingsRepository(userDefaults: UserDefaults(suiteName: "com.claudebar.test.\(UUID().uuidString)")!)
            settings.setEnabled(true, forProvider: "codex")
            let home = try CodexConfigSpec.makeHome()
            defer { try? FileManager.default.removeItem(at: home) }
            try CodexConfigSpec.writeAuth(in: home)

            let transport = MockRPCTransport()
            let received = ReceiveCounter()
            given(transport).send(.any).willReturn(())
            given(transport).close().willReturn(())
            given(transport).receive().willProduce { @Sendable in
                Data((received.next() == 1
                    ? #"{"id":1,"result":{}}"#
                    : #"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":20}}}}"#).utf8)
            }
            let network = MockNetworkClient()
            given(network).request(.any).willReturn((
                Data(#"{"rate_limit":{"primary_window":{"used_percent":55}}}"#.utf8),
                HTTPURLResponse(url: URL(string: "https://chatgpt.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            ))
            let codex = try CodexConfigSpec.makeCodex(settings: settings, home: home, network: network, transport: transport)

            // Default is RPC mode
            #expect(codex.provider.activeKind == "rpc")

            // When — user switches to API mode
            codex.provider.use("api")
            let monitor = QuotaMonitor(providers: AIProviders(providers: [codex]), clock: CodexConfigSpec.TestClock())
            await monitor.refresh(providerId: "codex")

            // Then — the API's answer (45% left) is shown, not RPC's (80%)
            #expect(codex.provider.activeKind == "api")
            #expect(codex.snapshot?.quotas.first?.percentRemaining == 45)
        }

        @Test
        func `the mode the card saves is the mode the provider uses`() throws {
            // Given
            let settings = UserDefaultsProviderSettingsRepository(userDefaults: UserDefaults(suiteName: "com.claudebar.test.\(UUID().uuidString)")!)
            let home = try CodexConfigSpec.makeHome()
            defer { try? FileManager.default.removeItem(at: home) }
            let codex = try CodexConfigSpec.makeCodex(settings: settings, home: home)
            #expect(settings.codexProbeMode() == .rpc)

            // When — the Codex card saves API mode
            settings.setCodexProbeMode(.api)

            // Then — persisted, and the provider follows it
            #expect(settings.codexProbeMode() == .api)
            #expect(codex.provider.activeKind == "api")
        }
    }

    // MARK: - #351: A failed key lookup names its step

    @Suite("Scenario: A failed key lookup names its step")
    @MainActor
    struct FailedLookupNamesItsStep {

        @Test
        func `the last usage stays, the lookup step is named, and its source is kept`() async throws {
            // Given — Codex on its API data source, showing usage
            let settings = UserDefaultsProviderSettingsRepository(userDefaults: UserDefaults(suiteName: "com.claudebar.test.\(UUID().uuidString)")!)
            let home = try CodexConfigSpec.makeHome()
            defer { try? FileManager.default.removeItem(at: home) }
            try CodexConfigSpec.writeAuth(in: home)
            let network = MockNetworkClient()
            given(network).request(.any).willReturn((
                Data(#"{"rate_limit":{"primary_window":{"used_percent":38}}}"#.utf8),
                HTTPURLResponse(url: URL(string: "https://chatgpt.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            ))
            let codex = try CodexConfigSpec.makeCodex(settings: settings, home: home, network: network)
            codex.provider.use("api")
            try await codex.refresh()

            // When — the key is gone and Codex refreshes
            try FileManager.default.removeItem(at: home.appendingPathComponent(".codex/auth.json"))
            await #expect(throws: (any Error).self) { try await codex.refresh() }

            // Then — the popover can say "Couldn't read your key", with the
            // last usage still on screen, last seen via API
            #expect(codex.lastFailedStep == .lookup)
            #expect(codex.snapshot?.quotas.first?.percentRemaining == 62)
            #expect(codex.answeredByLabel == "API")
        }
    }

    // MARK: - #34: API mode credential availability

    @Suite("Scenario: API mode credential availability")
    @MainActor
    struct CredentialStatus {

        @Test
        func `no OAuth credentials are found until codex has logged in`() throws {
            let settings = UserDefaultsProviderSettingsRepository(userDefaults: UserDefaults(suiteName: "com.claudebar.test.\(UUID().uuidString)")!)
            let home = try CodexConfigSpec.makeHome()
            defer { try? FileManager.default.removeItem(at: home) }
            let codex = try CodexConfigSpec.makeCodex(settings: settings, home: home)

            #expect(codex.hasKey(for: "api") == false)

            try CodexConfigSpec.writeAuth(in: home)

            #expect(codex.hasKey(for: "api") == true)
        }
    }
}

/// Counts calls across a mock's closure.
final class ReceiveCounter: @unchecked Sendable {
    private var value = 0
    private let lock = NSLock()

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}
