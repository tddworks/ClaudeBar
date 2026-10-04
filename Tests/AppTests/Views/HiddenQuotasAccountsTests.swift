import Domain
import Foundation
import Infrastructure
import Providers
import Testing
@testable import ClaudeBar

/// Hidden quotas belong to the product (#140): Gemini's models are the same
/// for every Gemini login, so hiding one hides it for all of them.
@MainActor
@Suite
struct HiddenQuotasAccountsTests {
    @Test
    func `every account of a product shares its hidden quotas`() throws {
        let settings = JSONSettingsRepository(store: JSONSettingsStore(
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("hidden-\(UUID().uuidString).json")))
        settings.setHiddenQuotaKeys(["model:codex-spark"], forProvider: "codex")
        let codex = try Providers.make("codex", settings: settings, accounts: [
            ProviderAccountConfig(accountId: "work", label: "", probeConfig: ["codexHome": "/tmp/w", "chatgptAccountId": "w"]),
        ])
        let monitor = QuotaMonitor(providers: AIProviders(providers: codex.accounts), clock: SystemClock(), settingsRepository: settings)

        #expect(monitor.hiddenQuotaKeys(for: codex.accounts[0]) == ["model:codex-spark"])
        #expect(monitor.hiddenQuotaKeys(for: codex.accounts[1]) == ["model:codex-spark"])
    }
}
