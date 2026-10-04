import DataSources
import Foundation
import Mockable
import Providers
import Quotas
import Testing

/// Mistral has no meter: its Vibe session logs are today's usage, shown as
/// TODAY'S USAGE beside it. The definition only says Vibe is installed.
@MainActor @Suite
struct MistralDefinitionTests {
    private func make(withLogs: Bool) throws -> (Provider, () -> Void) {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        if withLogs {
            try FileManager.default.createDirectory(at: home.appendingPathComponent(".vibe/logs/session/session_20260103_101500_abc"),
                                                    withIntermediateDirectories: true)
        }
        let definition = try Providers.builtIn("mistral")
        let provider = Provider(definition: definition, settings: InMemoryProviderSettings(), makeDataSource: { source, _ in
            DataSources.make(source, providerId: definition.id, cliExecutor: MockCLIExecutor(), network: MockNetworkClient(),
                             makeTransport: { _, _, _, _ in MockRPCTransport() }, scripts: Providers.builtInScripts,
                             environment: { _ in nil }, homeDirectory: home, now: { Date() })
        })
        return (provider, { try? FileManager.default.removeItem(at: home) })
    }

    @Test func `definition keeps Mistral's identity, off until turned on`() throws {
        let (provider, cleanUp) = try make(withLogs: true)
        defer { cleanUp() }
        #expect(provider.name == "Mistral")
        #expect(!provider.defaultAccount.isEnabled)
        #expect(provider.defaultAccount.dashboardURL?.absoluteString == "https://console.mistral.ai")
    }

    @Test func `with Vibe's logs it is available and reports no quota, never a made-up one`() async throws {
        let (provider, cleanUp) = try make(withLogs: true)
        defer { cleanUp() }
        #expect(await provider.defaultAccount.isAvailable())
        let usage = try await provider.defaultAccount.refresh()
        #expect(usage.quotas.isEmpty)
        #expect(usage.costUsage == nil)
    }

    @Test func `without Vibe it isn't available`() async throws {
        let (provider, cleanUp) = try make(withLogs: false)
        defer { cleanUp() }
        #expect(await provider.defaultAccount.isAvailable() == false)
    }
}
