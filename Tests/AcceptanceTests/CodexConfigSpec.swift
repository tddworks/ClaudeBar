import Monitoring
import Testing
import Foundation
import Mockable
import DataSources
import Providers

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
    ) throws -> Provider {
        let definition = try ProviderFactory.builtIn("codex")
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
        )
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
        func `should show the API's quotas, not the app server's, after the person switches Codex to API mode`() async throws {
            // Given — isolated settings, credentials, and both endpoints answering
            let settings = isolatedSettings()
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
            let codexProduct = try CodexConfigSpec.makeCodex(settings: settings, home: home, network: network, transport: transport)
            let codex = codexProduct.defaultAccount

            // Default is RPC mode
            #expect(codexProduct.configuration.activeKind == "rpc")

            // When — user switches to API mode
            codexProduct.configuration.use("api")
            let monitor = QuotaMonitor(providers: kept([codexProduct]), clock: CodexConfigSpec.TestClock())
            await monitor.refresh(providerId: "codex")

            // Then — the API's answer (45% left) is shown, not RPC's (80%)
            #expect(codexProduct.configuration.activeKind == "api")
            #expect(codex.snapshot?.quotas.first?.percentRemaining == 45)
        }

        @Test
        func `should use the data source the Codex card saves, RPC by default`() throws {
            // Given
            let settings = isolatedSettings()
            let home = try CodexConfigSpec.makeHome()
            defer { try? FileManager.default.removeItem(at: home) }
            let codexProduct = try CodexConfigSpec.makeCodex(settings: settings, home: home)
            let codex = codexProduct.defaultAccount
            #expect(codexProduct.configuration.activeKind == "rpc")

            // When — the Codex card saves API mode
            settings.setDataSourceKind("api", forProvider: "codex")

            // Then — persisted, and the provider follows it
            #expect(settings.dataSourceKind(forProvider: "codex") == "api")
            #expect(codexProduct.configuration.activeKind == "api")
        }
    }

    // MARK: - #351: A failed key lookup names its step

    @Suite("Scenario: A failed key lookup names its step")
    @MainActor
    struct FailedLookupNamesItsStep {

        @Test
        func `should keep the last usage and its source, and say the key couldn't be read, when the Codex key disappears (#351)`() async throws {
            // Given — Codex on its API data source, showing usage
            let settings = isolatedSettings()
            let home = try CodexConfigSpec.makeHome()
            defer { try? FileManager.default.removeItem(at: home) }
            try CodexConfigSpec.writeAuth(in: home)
            let network = MockNetworkClient()
            given(network).request(.any).willReturn((
                Data(#"{"rate_limit":{"primary_window":{"used_percent":38}}}"#.utf8),
                HTTPURLResponse(url: URL(string: "https://chatgpt.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            ))
            let codexProduct = try CodexConfigSpec.makeCodex(settings: settings, home: home, network: network)
            let codex = codexProduct.defaultAccount
            codexProduct.configuration.use("api")
            try await codexProduct.refresh(codex)

            // When — the key is gone and Codex refreshes
            try FileManager.default.removeItem(at: home.appendingPathComponent(".codex/auth.json"))
            await #expect(throws: (any Error).self) { try await codexProduct.refresh(codex) }

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
        func `should find no API key until the person has logged in to Codex`() throws {
            let settings = isolatedSettings()
            let home = try CodexConfigSpec.makeHome()
            defer { try? FileManager.default.removeItem(at: home) }
            let codexProduct = try CodexConfigSpec.makeCodex(settings: settings, home: home)
            let codex = codexProduct.defaultAccount

            #expect(codexProduct.hasKey(for: "api", account: codex) == false)

            try CodexConfigSpec.writeAuth(in: home)

            #expect(codexProduct.hasKey(for: "api", account: codex) == true)
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
