import DataSources
import Quotas
import Foundation
import Providers
import Testing

/// What an account is called: the name the person gave it, else the email
/// its login holds, else the product's name — and the product's name alone
/// while it is the only login to tell apart.
@MainActor
@Suite
struct AccountNamesTests {
    private func login(_ id: String, email: String?, label: String = "") -> ProviderAccountConfig {
        ProviderAccountConfig(accountId: id, label: label, email: email, probeConfig: ["codexHome": "/tmp/\(id)", "chatgptAccountId": id])
    }

    private func codex(_ settings: InMemoryProviderSettings, _ logins: [ProviderAccountConfig] = []) throws -> Provider {
        try ProviderFactory.make("codex", settings: settings, accounts: logins)
    }

    // MARK: - Display name

    @Test
    func `should call a login by its label, else its email, else the product's name`() throws {
        let codex = try codex(InMemoryProviderSettings(), [
            login("a", email: "a@example.com", label: "Work"),
            login("b", email: "b@example.com"),
        ])

        #expect(codex.accounts[1].displayName == "Work")
        #expect(codex.accounts[2].displayName == "b@example.com")
        #expect(codex.defaultAccount.displayName == "Codex")
    }

    @Test
    func `should show the email when a login's label is blank`() throws {
        let codex = try codex(InMemoryProviderSettings(), [login("a", email: "a@example.com", label: "   ")])

        #expect(codex.accounts[1].displayName == "a@example.com")
    }

    // MARK: - The pill's name

    @Test
    func `should call a single login by the product's name`() throws {
        let codex = try codex(InMemoryProviderSettings())

        #expect(codex.accounts.hasSeveral == false)
        #expect(codex.lineupName(of: codex.defaultAccount) == "Codex")
    }

    @Test
    func `should call several logins by their display names`() throws {
        let codex = try codex(InMemoryProviderSettings(), [login("a", email: "a@example.com", label: "Work")])

        #expect(codex.accounts.hasSeveral)
        #expect(codex.accounts.map(codex.lineupName(of:)) == ["Codex", "Work"])
    }

    @Test
    func `should stop telling a login apart when the other is paused`() throws {
        let codex = try codex(InMemoryProviderSettings(), [login("a", email: "a@example.com")])

        codex.accounts[1].isPaused = true

        #expect(codex.accounts.hasSeveral == false)
        #expect(codex.lineupName(of: codex.defaultAccount) == "Codex")
    }

    // MARK: - Rename

    @Test
    func `should save a renamed login's label and keep who it is`() throws {
        let settings = InMemoryProviderSettings()
        let work = login("a", email: "a@example.com")
        settings.addAccount(work, forProvider: "codex")
        let codex = try codex(settings, [work])

        codex.accounts.rename(codex.accounts[1], to: "  Acme  ")

        #expect(codex.accounts[1].displayName == "Acme")
        #expect(settings.accounts(forProvider: "codex").first?.label == "Acme")
        #expect(settings.accounts(forProvider: "codex").first?.probeConfig == work.probeConfig)
        #expect(codex.accounts[1].id == "codex.a")
    }

    @Test
    func `should keep the default login's name after a relaunch`() throws {
        let settings = InMemoryProviderSettings()
        let first = try codex(settings)
        first.accounts.rename(first.defaultAccount, to: "Personal")

        let relaunched = try codex(settings)

        #expect(relaunched.defaultAccount.displayName == "Personal")
    }

    @Test
    func `should go back to the email when a login's name is cleared`() throws {
        let settings = InMemoryProviderSettings()
        let work = login("a", email: "a@example.com", label: "Acme")
        settings.addAccount(work, forProvider: "codex")
        let codex = try codex(settings, [work])

        codex.accounts.rename(codex.accounts[1], to: "")

        #expect(codex.accounts[1].displayName == "a@example.com")
        #expect(settings.accounts(forProvider: "codex").first?.label == "")
    }

    // MARK: - Remove

    @Test
    func `should forget an added login's saved settings when it is removed`() throws {
        let settings = InMemoryProviderSettings()
        let work = login("a", email: "a@example.com")
        settings.addAccount(work, forProvider: "codex")
        let codex = try codex(settings, [work])

        codex.accounts.remove(codex.accounts[1])

        #expect(codex.accounts.count == 1)
        #expect(settings.accounts(forProvider: "codex").isEmpty)
    }

    @Test
    func `should keep the default login when asked to remove it`() throws {
        let codex = try codex(InMemoryProviderSettings())

        codex.accounts.remove(codex.defaultAccount)

        #expect(codex.accounts.count == 1)
    }
}
