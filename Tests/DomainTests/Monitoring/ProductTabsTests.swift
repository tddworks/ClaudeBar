import Foundation
import Testing
@testable import Domain
@testable import Infrastructure

/// Settings → Providers, by product (CANONICAL §1: the product's switch): one row per
/// product, its switch hiding every login, its logins moving together.
@MainActor
@Suite
struct ProductTabsTests {
    private let temp = FileManager.default.temporaryDirectory.appendingPathComponent("product-tabs-\(UUID().uuidString)")

    /// Codex with two logins (*me* and *work*), then Claude with one.
    private func monitor() throws -> (QuotaMonitor, codex: Provider, claude: Provider) {
        let settings = JSONSettingsRepository(store: JSONSettingsStore(fileURL: temp.appendingPathComponent("settings.json")))
        let work = ProviderAccountConfig(accountId: "work", label: "work", probeConfig: ["folder": "/tmp/work", "accountId": "work"])
        let codex = try ProviderFactory.make("codex", settings: settings, accounts: [work])
        let claude = try ProviderFactory.make("claude", settings: settings)
        return (QuotaMonitor(providers: kept([codex, claude])), codex, claude)
    }

    @Test
    func `should list each provider once with all its logins, whether on or off`() throws {
        let (monitor, codex, _) = try monitor()
        codex.accounts[1].isPaused = true

        let tabs = monitor.productTabs

        #expect(tabs.map(\.id) == ["codex", "claude"])
        #expect(tabs[0].logins.count == 2)
    }

    @Test
    func `should hide every login of a provider the person turns off, keeping each login's own switch`() throws {
        let (monitor, codex, _) = try monitor()

        monitor.setProductEnabled(monitor.productTabs[0], enabled: false)

        #expect(!monitor.productTabs[0].isEnabled)
        #expect(!monitor.lineup.contains { $0.id.hasPrefix("codex") })
        #expect(codex.accounts.allSatisfy { !$0.isPaused } == true)
    }

    @Test
    func `should select another provider when the person turns off the selected one`() throws {
        let (monitor, _, _) = try monitor()
        monitor.selectedProviderId = "codex"

        monitor.setProductEnabled(monitor.productTabs[0], enabled: false)

        #expect(monitor.selectedProviderId == "claude")
    }

    @Test
    func `should move a provider's logins together when the person moves the provider`() throws {
        let (monitor, _, _) = try monitor()

        monitor.providers.move("claude", by: -1)

        #expect(monitor.productTabs.map(\.id) == ["claude", "codex"])
        #expect(monitor.logins.map(\.id).prefix(1) == ["claude"])
        #expect(monitor.logins.map(\.id).suffix(2) == ["codex", "codex.work"])
    }

    @Test
    func `should name each login only when the provider has several`() throws {
        let (monitor, codex, claude) = try monitor()
        codex.accounts.rename(codex.defaultAccount, to: "personal")

        #expect(monitor.productTabs[0].loginName(codex.defaultAccount) == "personal")
        #expect(monitor.productTabs[0].loginName(codex.accounts[1]) == "work")
        #expect(monitor.productTabs[1].loginName(claude.defaultAccount) == nil)
    }

    @Test
    func `should show the plain login's settings on a provider's page`() throws {
        let (monitor, codex, _) = try monitor()

        #expect(monitor.productTabs[0].page === codex.defaultAccount)
    }
}
