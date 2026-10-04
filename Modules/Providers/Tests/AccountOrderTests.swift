import DataSources
import Foundation
import Providers
import Quotas
import Testing

/// The order of a provider's logins is the person's: *Personal* above
/// *Work* is a preference, not a fact about the CLI — so the default login
/// moves like the others and is found by being the default, not by being first.
@MainActor
@Suite
struct AccountOrderTests {
    private func login(_ id: String) -> ProviderAccountConfig {
        ProviderAccountConfig(accountId: id, label: id.capitalized, email: "\(id)@example.com",
                              probeConfig: ["codexHome": "/tmp/\(id)", "chatgptAccountId": id])
    }

    private func codex(_ settings: InMemoryProviderSettings) throws -> Provider {
        try Providers.make("codex", settings: settings, accounts: settings.accounts(forProvider: "codex"))
    }

    private func saved(_ ids: String...) -> InMemoryProviderSettings {
        let settings = InMemoryProviderSettings()
        for id in ids { settings.addAccount(login(id), forProvider: "codex") }
        return settings
    }

    @Test
    func `logins start in the order they were added, the default first`() throws {
        let codex = try codex(saved("work", "side"))

        #expect(codex.accounts.map(\.accountId) == ["default", "work", "side"])
    }

    @Test
    func `a moved login keeps its place after a relaunch`() throws {
        let settings = saved("work", "side")
        let first = try codex(settings)

        first.move(first.accounts[2], to: 0)

        #expect(first.accounts.map(\.accountId) == ["side", "default", "work"])
        #expect(try codex(settings).accounts.map(\.accountId) == ["side", "default", "work"])
    }

    @Test
    func `the default login is found wherever it sits`() throws {
        let codex = try codex(saved("work"))

        codex.move(codex.defaultAccount, to: 1)

        #expect(codex.defaultAccount.isDefault)
        #expect(codex.defaultAccount.id == "codex")
        #expect(codex.accounts.map(\.accountId) == ["work", "default"])
    }

    @Test
    func `a login added later joins the end of the saved order`() throws {
        let settings = saved("work", "side")
        let first = try codex(settings)
        first.move(first.accounts[2], to: 0)

        first.add(login("new"))

        #expect(try codex(settings).accounts.map(\.accountId) == ["side", "default", "work", "new"])
    }

    @Test
    func `moving past the end puts the login last`() throws {
        let codex = try codex(saved("work", "side"))

        codex.move(codex.accounts[0], to: 99)

        #expect(codex.accounts.map(\.accountId) == ["work", "side", "default"])
    }
}
