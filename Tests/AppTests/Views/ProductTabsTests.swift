import DataSources
import Domain
import Foundation
import Infrastructure
import Providers
import Quotas
import Testing
@testable import ClaudeBar

/// The popover's pills are products: a provider's logins share one tab, in
/// the order the person gave them, and ⌘1 is the first tab.
@MainActor
@Suite
struct ProductTabsTests {
    private func settings() -> JSONSettingsRepository {
        JSONSettingsRepository(store: JSONSettingsStore(
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("tabs-\(UUID().uuidString).json")))
    }

    private func login(_ id: String) -> ProviderAccountConfig {
        ProviderAccountConfig(accountId: id, label: id.capitalized, email: "\(id)@example.com",
                              probeConfig: ["codexHome": "/tmp/\(id)", "chatgptAccountId": id])
    }

    private func lineup() throws -> (claude: Provider, codex: Provider, all: [any AIProvider]) {
        let settings = settings()
        let claude = try Providers.make("claude", settings: settings)
        let codex = try Providers.make("codex", settings: settings, accounts: [login("work"), login("side")])
        return (claude, codex, claude.accounts + codex.accounts)
    }

    @Test
    func `a provider's logins share one tab`() throws {
        let (_, codex, all) = try lineup()

        let tabs = ProductTab.tabs(of: all)

        #expect(tabs.map(\.id) == ["claude", "codex"])
        #expect(tabs[1].accounts.map(\.id) == codex.accounts.map(\.id))
        #expect(tabs[1].name == "Codex")
    }

    @Test
    func `a tab keeps the person's order and leaves out paused logins`() throws {
        let (_, codex, _) = try lineup()
        codex.move(codex.accounts[2], to: 0)
        codex.accounts[1].isEnabled = false
        let shown = (codex.accounts.filter(\.isEnabled) as [any AIProvider])

        let tab = try #require(ProductTab.tabs(of: shown).first)

        #expect(tab.accounts.map(\.id) == ["codex.side", "codex.work"])
    }

    @Test
    func `a tab knows every login it holds`() throws {
        let (_, _, all) = try lineup()

        let codex = try #require(ProductTab.tabs(of: all).last)

        #expect(codex.contains("codex.work"))
        #expect(codex.contains("codex"))
        #expect(!codex.contains("claude"))
    }

    @Test
    func `the monitor selects by tab position and knows the selected tab`() throws {
        let (_, codex, all) = try lineup()
        let monitor = QuotaMonitor(providers: AIProviders(providers: all), clock: SystemClock())

        monitor.selectProvider(atPosition: 2)

        #expect(monitor.selectedTab?.id == "codex")
        #expect(monitor.selectedProviderId == codex.accounts[0].id)
        monitor.selectedProviderId = "codex.side"
        #expect(monitor.selectedTab?.id == "codex")
    }
}
