import Foundation
import Providers
import Testing

/// *The product's switch* (CANONICAL §1: the product's switch): Claude on or off hides every
/// login of it, and keeps each login's own *Pause*. On upgrade, the old
/// switch — which was the plain login's — keeps meaning what it did.
@MainActor
@Suite
struct ProductSwitchTests {
    private func work() -> ProviderAccountConfig {
        ProviderAccountConfig(accountId: "work", label: "work", probeConfig: ["codexHome": "/tmp/work", "chatgptAccountId": "work"])
    }

    private func codex(_ settings: InMemoryProviderSettings) throws -> Provider {
        try ProviderFactory.make("codex", settings: settings, accounts: settings.accounts(forProvider: "codex"))
    }

    private func twoLogins() -> InMemoryProviderSettings {
        let settings = InMemoryProviderSettings()
        settings.addAccount(work(), forProvider: "codex")
        return settings
    }

    @Test
    func `should show every login of a provider in the lineup when the provider is on`() throws {
        let codex = try codex(twoLogins())

        let shown = codex.accounts.filter(codex.isInLineup).count
        #expect(codex.isEnabled)
        #expect(shown == 2)
    }

    @Test
    func `should hide every login but keep each login's own switch when the provider is turned off`() throws {
        let codex = try codex(twoLogins())

        codex.isEnabled = false

        let shown = codex.accounts.filter(codex.isInLineup).count
        let on = codex.accounts.filter { !$0.isPaused }.count
        #expect(shown == 0)
        #expect(on == 2)
    }

    @Test
    func `should keep the provider on and its other logins shown when one login is paused`() throws {
        let codex = try codex(twoLogins())

        codex.defaultAccount.isPaused = true

        #expect(codex.isEnabled)
        #expect(!codex.plainIsInLineup)
        #expect(codex.isInLineup(codex.accounts[1]))
    }

    @Test
    func `should remember the provider's switch and a login's pause apart across a relaunch`() throws {
        let settings = twoLogins()
        let first = try codex(settings)
        first.defaultAccount.isPaused = true
        first.isEnabled = false

        let again = try codex(settings)

        #expect(!again.isEnabled)
        #expect(again.defaultAccount.isPaused)
        #expect(!again.accounts[1].isPaused)
    }

    // MARK: - Upgrade: the old switch was the plain login's

    @Test
    func `should pause only the plain login when the old switch was off and another login is on, after an upgrade`() throws {
        let settings = twoLogins()
        settings.setEnabled(false, forProvider: "codex")

        let codex = try codex(settings)

        #expect(codex.isEnabled)
        #expect(codex.defaultAccount.isPaused)
        #expect(codex.isInLineup(codex.accounts[1]))
    }

    @Test
    func `should turn the provider off when the old switch was off and no other login is on, after an upgrade`() throws {
        let settings = InMemoryProviderSettings()
        settings.setEnabled(false, forProvider: "codex")

        let codex = try codex(settings)

        #expect(!codex.isEnabled)
        #expect(!codex.defaultAccount.isPaused)
    }

    @Test
    func `should honour the old switch only once after an upgrade`() throws {
        let settings = twoLogins()
        settings.setEnabled(false, forProvider: "codex")
        let first = try codex(settings)
        first.defaultAccount.isPaused = false

        let again = try codex(settings)

        #expect(again.isEnabled)
        #expect(!again.defaultAccount.isPaused)
    }
}
