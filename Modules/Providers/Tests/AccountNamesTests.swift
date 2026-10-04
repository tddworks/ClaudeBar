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
        try Providers.make("codex", settings: settings, accounts: logins)
    }

    // MARK: - Display name

    @Test
    func `the display name is the label, else the email, else the product`() throws {
        let codex = try codex(InMemoryProviderSettings(), [
            login("a", email: "a@example.com", label: "Work"),
            login("b", email: "b@example.com"),
        ])

        #expect(codex.accounts[1].displayName == "Work")
        #expect(codex.accounts[2].displayName == "b@example.com")
        #expect(codex.defaultAccount.displayName == "Codex")
    }

    @Test
    func `a blank label does not hide the email`() throws {
        let codex = try codex(InMemoryProviderSettings(), [login("a", email: "a@example.com", label: "   ")])

        #expect(codex.accounts[1].displayName == "a@example.com")
    }

    // MARK: - The pill's name

    @Test
    func `a single login is called by the product's name`() throws {
        let codex = try codex(InMemoryProviderSettings())

        #expect(codex.hasSeveralAccounts == false)
        #expect(codex.defaultAccount.name == "Codex")
    }

    @Test
    func `several logins are called by their display names`() throws {
        let codex = try codex(InMemoryProviderSettings(), [login("a", email: "a@example.com", label: "Work")])

        #expect(codex.hasSeveralAccounts)
        #expect(codex.accounts.map(\.name) == ["Codex", "Work"])
    }

    @Test
    func `a paused login no longer needs telling apart`() throws {
        let codex = try codex(InMemoryProviderSettings(), [login("a", email: "a@example.com")])

        codex.accounts[1].isEnabled = false

        #expect(codex.hasSeveralAccounts == false)
        #expect(codex.defaultAccount.name == "Codex")
    }

    // MARK: - Rename

    @Test
    func `renaming an added login saves its label and keeps who it is`() throws {
        let settings = InMemoryProviderSettings()
        let work = login("a", email: "a@example.com")
        settings.addAccount(work, forProvider: "codex")
        let codex = try codex(settings, [work])

        codex.rename(codex.accounts[1], to: "  Acme  ")

        #expect(codex.accounts[1].displayName == "Acme")
        #expect(settings.accounts(forProvider: "codex").first?.label == "Acme")
        #expect(settings.accounts(forProvider: "codex").first?.probeConfig == work.probeConfig)
        #expect(codex.accounts[1].id == "codex.a")
    }

    @Test
    func `the default login's name survives a relaunch`() throws {
        let settings = InMemoryProviderSettings()
        let first = try codex(settings)
        first.rename(first.defaultAccount, to: "Personal")

        let relaunched = try codex(settings)

        #expect(relaunched.defaultAccount.displayName == "Personal")
    }

    @Test
    func `clearing a name goes back to the email`() throws {
        let settings = InMemoryProviderSettings()
        let work = login("a", email: "a@example.com", label: "Acme")
        settings.addAccount(work, forProvider: "codex")
        let codex = try codex(settings, [work])

        codex.rename(codex.accounts[1], to: "")

        #expect(codex.accounts[1].displayName == "a@example.com")
        #expect(settings.accounts(forProvider: "codex").first?.label == "")
    }

    // MARK: - Remove

    @Test
    func `removing an added login forgets its saved settings`() throws {
        let settings = InMemoryProviderSettings()
        let work = login("a", email: "a@example.com")
        settings.addAccount(work, forProvider: "codex")
        let codex = try codex(settings, [work])

        codex.remove(codex.accounts[1])

        #expect(codex.accounts.count == 1)
        #expect(settings.accounts(forProvider: "codex").isEmpty)
    }

    @Test
    func `the default login cannot be removed`() throws {
        let codex = try codex(InMemoryProviderSettings())

        codex.remove(codex.defaultAccount)

        #expect(codex.accounts.count == 1)
    }
}
