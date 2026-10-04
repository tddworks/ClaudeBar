import DataSources
import Domain
import Foundation
import Infrastructure
import Providers
import Testing
@testable import ClaudeBar

/// The words of the Accounts card, from the definition — so every provider
/// that can have accounts gets the same card with no `switch` on its id.
@MainActor
@Suite
struct AccountsCardTextTests {
    private func codex(_ logins: [ProviderAccountConfig] = []) throws -> Provider {
        let settings = JSONSettingsRepository(store: JSONSettingsStore(
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("accounts-card-\(UUID().uuidString).json")))
        return try Providers.make("codex", settings: settings, accounts: logins)
    }

    private func login(_ id: String, folder: String, madeBy: AccountOrigin) -> ProviderAccountConfig {
        ProviderAccountConfig(accountId: id, label: "", email: "\(id)@example.com",
                              probeConfig: ["codexHome": folder, "chatgptAccountId": id], madeBy: madeBy)
    }

    @Test
    func `the count says how many logins there are`() throws {
        #expect(AccountsCardText(provider: try codex()).count == "1 account")
        #expect(AccountsCardText(provider: try codex([login("a", folder: "/tmp/a", madeBy: .folder)])).count == "2 accounts")
    }

    @Test
    func `the ways to add are the definition's, easiest first`() throws {
        let text = AccountsCardText(provider: try codex())

        #expect(text.ways.map(\.label) == ["Sign in with browser", "Choose Signed-in Folder"])
    }

    @Test
    func `a provider someone added asks for its key`() throws {
        var draft = ProviderDraft(start: .api)
        draft.url = "https://openrouter.ai/api/v1/auth/key"
        draft.key = .apiKey
        draft.measure = .percentUsed
        draft.used = "$.used"
        draft.name = "OpenRouter"
        let settings = JSONSettingsRepository(store: JSONSettingsStore(
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("accounts-card-\(UUID().uuidString).json")))
        let provider = Providers.make(try draft.definition(id: "custom-openrouter"), settings: settings)

        #expect(AccountsCardText(provider: provider).ways.map(\.label) == ["Enter API key"])
    }

    @Test
    func `an API account is described and recovered without mentioning a CLI or folder`() throws {
        let settings = JSONSettingsRepository(store: JSONSettingsStore(
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("accounts-card-\(UUID()).json")))
        let provider = try Providers.make("deepseek", settings: settings,
                                          accounts: [ProviderAccountConfig(accountId: "work", label: "Work", probeConfig: [:], madeBy: .form)])
        let text = AccountsCardText(provider: provider)
        #expect(text.defaultLoginDescription == "Default account")
        #expect(text.reauthHelp(for: provider.defaultAccount) == "Update the default account's key in Settings, then refresh.")
        #expect(text.reauthHelp(for: provider.accounts[1]) == "Remove this account and add it again with a valid key.")
        #expect(text.removeMessage(for: provider.accounts[1]) == "Removes Work from ClaudeBar and deletes its saved keys.")
    }

    @Test
    func `signing in yourself uses the definition's own command`() throws {
        let text = AccountsCardText(provider: try codex())

        #expect(text.signInCommand(in: "/Users/me/work") == #"CODEX_HOME=/Users/me/work codex -c 'cli_auth_credentials_store="file"' login"#)
    }

    @Test
    func `a folder with a space survives being pasted into a terminal`() throws {
        let text = AccountsCardText(provider: try codex())

        #expect(text.signInCommand(in: "/Users/me/My Work")?.hasPrefix("CODEX_HOME='/Users/me/My Work' codex") == true)
    }

    @Test
    func `removing says what goes with the account`() throws {
        let made = "/Users/me/.claudebar/accounts/codex/\(UUID().uuidString.lowercased())"
        let provider = try codex([login("a", folder: made, madeBy: .signIn), login("b", folder: "/Users/me/codex-b", madeBy: .folder)])
        let text = AccountsCardText(provider: provider)

        #expect(text.removeMessage(for: provider.accounts[1]) == "Removes a@example.com from ClaudeBar and deletes the sign-in ClaudeBar kept for it.")
        #expect(text.removeMessage(for: provider.accounts[2]) == "Removes b@example.com from ClaudeBar. Its login and folder stay where they are.")
    }

    @Test
    func `a login ClaudeBar made signs in again from the card, one the person chose is told how`() throws {
        let made = "/Users/me/.claudebar/accounts/codex/\(UUID().uuidString.lowercased())"
        let provider = try codex([login("a", folder: made, madeBy: .signIn), login("b", folder: "/Users/me/codex-b", madeBy: .folder)])
        let text = AccountsCardText(provider: provider)

        #expect(text.reauthHelp(for: provider.accounts[1]) == nil)
        #expect(text.reauthHelp(for: provider.accounts[2]) == #"Sign in again yourself: CODEX_HOME=/Users/me/codex-b codex -c 'cli_auth_credentials_store="file"' login — then refresh."#)
    }

    @Test func `a path form keeps its folder and asks for CLI sign-in rather than a new key`() throws {
        let json = #"{"profile":{"id":"example","name":"Example"},"cli":"example","defaultDataSource":"file","dataSources":[{"kind":"file","fetch":{"file":{"path":"/tmp/example.json"}},"mapping":{"json":{"quotas":[]}}}],"settings":[{"id":"home","label":"Home Folder","scope":"account","kind":"path"}],"accounts":{"patch":{}}}"#
        let settings = JSONSettingsRepository(store: JSONSettingsStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        let account = ProviderAccountConfig(accountId: "work", label: "Work", probeConfig: ["home": "/tmp/work profile"], madeBy: .form)
        let provider = Providers.make(try ProviderDefinition.parse(Data(json.utf8)), settings: settings, accounts: [account])
        let text = AccountsCardText(provider: provider)

        #expect(text.removeMessage(for: provider.accounts[1]) == "Removes Work from ClaudeBar. Its login and folder stay where they are.")
        #expect(text.reauthHelp(for: provider.accounts[1]) == "Sign in again in /tmp/work profile with your CLI, then refresh.")
    }

    @Test func `the default login's re-sign-in help is its key lookup's own hint`() throws {
        let json = #"{"profile":{"id":"example","name":"Example"},"defaultDataSource":"api","dataSources":[{"kind":"api","credential":{"sqlite":{"path":"~/example.db","query":"SELECT 1","fields":{},"hint":"Sign in again in Example, then refresh."}},"fetch":{"http":{"url":"https://example.test"}},"mapping":{"json":{"quotas":[]}}}]}"#
        let settings = JSONSettingsRepository(store: JSONSettingsStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        let provider = Providers.make(try ProviderDefinition.parse(Data(json.utf8)), settings: settings)

        #expect(AccountsCardText(provider: provider).reauthHelp(for: provider.defaultAccount) == "Sign in again in Example, then refresh.")
    }
}
