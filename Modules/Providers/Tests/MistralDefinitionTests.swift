import DataSources
import Foundation
import Mockable
import Providers
import Quotas
import Testing

/// Mistral's Vibe session logs are today's usage, shown as TODAY'S USAGE;
/// the plan meter comes from the web source (#496) when a cookie is pasted.
@MainActor @Suite
struct MistralDefinitionTests {
    private func make(withLogs: Bool) throws -> (Provider, () -> Void) {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        if withLogs {
            try FileManager.default.createDirectory(at: home.appendingPathComponent(".vibe/logs/session/session_20260103_101500_abc"),
                                                    withIntermediateDirectories: true)
        }
        let definition = try ProviderFactory.builtIn("mistral")
        let provider = Provider(definition: definition, settings: InMemoryProviderSettings(), makeDataSource: { source, _ in
            DataSources.make(source, providerId: definition.id, cliExecutor: MockCLIExecutor(), network: MockNetworkClient(),
                             makeTransport: { _, _, _, _ in MockRPCTransport() }, scripts: ProviderFactory.builtInScripts,
                             environment: { _ in nil }, homeDirectory: home, now: { Date() })
        })
        return (provider, { try? FileManager.default.removeItem(at: home) })
    }

    @Test func `should show Mistral with its console, off until the person turns it on`() throws {
        let (provider, cleanUp) = try make(withLogs: true)
        defer { cleanUp() }
        #expect(provider.name == "Mistral")
        #expect(!provider.plainIsInLineup)
        #expect(provider.plainDashboardURL?.absoluteString == "https://console.mistral.ai")
    }

    @Test func `should be available with no quota, never a made-up one, when Vibe has logs`() async throws {
        let (provider, cleanUp) = try make(withLogs: true)
        defer { cleanUp() }
        #expect(await provider.isPlainAvailable())
        let usage = try await provider.refreshPlain()
        #expect(usage.quotas.isEmpty)
        #expect(usage.costUsage == nil)
    }

    @Test func `should be unavailable when Vibe is not installed`() async throws {
        let (provider, cleanUp) = try make(withLogs: false)
        defer { cleanUp() }
        #expect(await provider.isPlainAvailable() == false)
    }
}
