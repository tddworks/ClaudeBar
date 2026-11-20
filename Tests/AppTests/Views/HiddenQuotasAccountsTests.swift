import Foundation
import Providers
import Testing
@testable import ClaudeBar
import Monitoring
import Storage

/// Hidden quotas belong to the product (#140): Gemini's models are the same
/// for every Gemini login, so hiding one hides it for all of them.
@MainActor
@Suite
struct HiddenQuotasAccountsTests {
    @Test
    func `should hide a quota for every account of a provider once it is hidden (#140)`() throws {
        let settings = Storage.makeSettings(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("hidden-\(UUID().uuidString).json"))
        settings.setHiddenQuotaKeys(["model:codex-spark"], forProvider: "codex")
        let codex = try ProviderFactory.make("codex", settings: settings, accounts: [
            ProviderAccountConfig(accountId: "work", label: "", probeConfig: ["folder": "/tmp/w", "accountId": "w"]),
        ])
        let monitor = QuotaMonitor(providers: Providers([codex], make: { _ in fatalError("no providers added") }), clock: SystemClock(), settingsRepository: settings)

        #expect(monitor.hiddenQuotaKeys(for: codex.accounts[0]) == ["model:codex-spark"])
        #expect(monitor.hiddenQuotaKeys(for: codex.accounts[1]) == ["model:codex-spark"])
    }
}
