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

    private func lineup() throws -> (claude: Provider, codex: Provider, all: [Account], providers: Providers) {
        let settings = settings()
        let claude = try ProviderFactory.make("claude", settings: settings)
        let codex = try ProviderFactory.make("codex", settings: settings, accounts: [login("work"), login("side")])
        let providers = Providers([claude, codex], make: { _ in fatalError("no providers added") })
        return (claude, codex, Array(claude.accounts) + Array(codex.accounts), providers)
    }

    @Test
    func `should show a provider's logins under one tab`() throws {
        let (_, codex, _, providers) = try lineup()

        let tabs = ProductTab.tabs(in: providers)

        #expect(tabs.map(\.id) == ["claude", "codex"])
        #expect(tabs[1].logins.map(\.id) == codex.accounts.map(\.id))
        #expect(tabs[1].name == "Codex")
    }

    @Test
    func `should keep the person's order in a tab and take a paused login out of its chips`() throws {
        let (_, codex, _, providers) = try lineup()
        codex.accounts.move(codex.accounts[2], to: 0)
        codex.accounts[1].isEnabled = false

        let tab = try #require(ProductTab.tabs(in: providers).last)

        #expect(tab.logins.map(\.id) == ["codex.side", "codex", "codex.work"])
        #expect(tab.watched.map(\.id) == ["codex.side", "codex.work"])
        #expect(tab.paused.map(\.id) == ["codex"])
    }

    @Test
    func `should hold every one of its provider's logins in a tab, and no other's`() throws {
        let (_, _, _, providers) = try lineup()

        let codex = try #require(ProductTab.tabs(in: providers).last)

        #expect(codex.contains("codex.work"))
        #expect(codex.contains("codex"))
        #expect(!codex.contains("claude"))
    }

    @Test
    func `should select the second tab with ⌘2 and keep it selected for any of its logins`() throws {
        let (claude, codex, _, _) = try lineup()
        let monitor = QuotaMonitor(providers: Providers([claude, codex], make: { _ in fatalError("no providers added") }),
                                   clock: SystemClock())

        monitor.selectProvider(atPosition: 2)

        #expect(monitor.selectedTab?.id == "codex")
        #expect(monitor.selectedProviderId == codex.accounts[0].id)
        monitor.selectedProviderId = "codex.side"
        #expect(monitor.selectedTab?.id == "codex")
        #expect(monitor.selectedLogins.map(\.id) == codex.accounts.map(\.id))
    }
}
