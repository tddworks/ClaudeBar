import Testing
import Foundation
import Mockable
import DataSources
import Providers
@testable import Domain
@testable import Infrastructure

/// USER_JOURNEYS §5 — "Add a custom provider from an API". Ken pays for a
/// gateway ClaudeBar doesn't ship and tracks its credits without a script.
@Suite("Feature: Add Provider")
struct AddProviderSpec {

    final class Vault: SecretStore, @unchecked Sendable {
        var keys: [String: String] = [:]
        func secret(_ name: String, provider: String) -> String? { keys["provider.\(provider).\(name)"] }
    }

    @Suite("Scenario: Add a custom provider from an API")
    @MainActor
    struct FromAnAPI {

        @Test
        func `Ken adds OpenRouter and sees its credits, with no reset and no percentage`() async throws {
            // Given — Ken has an OpenRouter key
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("add-provider-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: folder) }
            let network = MockNetworkClient()
            given(network).request(.matching { @Sendable in $0.value(forHTTPHeaderField: "Authorization") == "Bearer sk-or-ken" })
                .willReturn((Data(#"{"data":{"label":"ken","limit":50,"limit_remaining":12.4}}"#.utf8),
                             HTTPURLResponse(url: URL(string: "https://openrouter.ai")!, statusCode: 200, httpVersion: nil, headerFields: nil)!))
            let vault = Vault()

            // When — he adds a provider from "API" with the auth/key URL and his key,
            // maps Remaining and Limit, names it "OpenRouter" and saves
            var draft = ProviderDraft(start: .api)
            draft.url = "https://openrouter.ai/api/v1/auth/key"
            draft.key = .apiKey
            draft.measure = .money(currency: "USD")
            draft.remaining = "$.data.limit_remaining"
            draft.limit = "$.data.limit"
            draft.name = "OpenRouter"
            let catalog = ProviderCatalog(directory: folder)
            let id = catalog.mintId(for: draft.name)
            try catalog.add(try draft.definition(id: id))
            vault.keys["provider.\(id).apiKey"] = "sk-or-ken"

            let saved = try #require(catalog.custom().first)
            let settings = UserDefaultsProviderSettingsRepository(userDefaults: UserDefaults(suiteName: "com.claudebar.test.\(UUID().uuidString)")!)
            let openRouter = Provider(definition: saved, settings: settings, makeDataSource: {
                DataSources.make($0, providerId: saved.id, cliExecutor: MockCLIExecutor(), network: network,
                                 makeTransport: { _, _, _, _ in MockRPCTransport() }, secrets: vault,
                                 environment: { _ in nil }, homeDirectory: folder, now: { Date() })
            }).defaultAccount
            let monitor = QuotaMonitor(providers: AIProviders(providers: [openRouter]), clock: ClaudeConfigSpec.TestClock())
            await monitor.refresh(providerId: openRouter.id)

            // Then — "OpenRouter" appears with $12.40 of $50.00, no reset and no percentage of a window
            #expect(saved.profile.origin == .custom)
            #expect(monitor.allProviders.map(\.name) == ["OpenRouter"])
            let credits = try #require(openRouter.snapshot?.quotas.first)
            #expect(credits.left == .money(Money(Decimal(string: "12.4")!, currency: "USD"), of: Money(50, currency: "USD")))
            #expect(credits.resetsAt == nil)
            #expect(credits.window == nil)
        }

        @Test
        func `the saved file names the key but never holds it`() throws {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("add-provider-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: folder) }
            var draft = ProviderDraft(start: .api)
            draft.url = "https://openrouter.ai/api/v1/auth/key"
            draft.used = "$.used"
            draft.name = "OpenRouter"
            let catalog = ProviderCatalog(directory: folder)
            let id = catalog.mintId(for: draft.name)
            try catalog.add(try draft.definition(id: id))

            let text = try String(contentsOf: folder.appendingPathComponent("\(id).json"), encoding: .utf8)

            #expect(text.contains("apiKey"))
            #expect(!text.contains("sk-"))
        }
    }
}
