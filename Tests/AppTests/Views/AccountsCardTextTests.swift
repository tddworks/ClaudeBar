import Kit
import Foundation
import Testing
@testable import ClaudeBar

/// The words of the Accounts card, from the definition — so every provider
/// that can have accounts gets the same card with no `switch` on its id.
@MainActor
@Suite
struct AccountsCardTextTests {
    private func codex(_ logins: [[String: Any]] = []) throws -> Provider {
        try TestKit.start(settings: TestKit.settings("codex", logins: logins)).provider("codex")
    }

    private func login(_ id: String, folder: String, madeBy: AccountOrigin) -> [String: Any] {
        TestKit.login(id, email: "\(id)@example.com", values: ["codexHome": folder, "chatgptAccountId": id], madeBy: madeBy)
    }

    @Test
    func `should say how many accounts the provider has`() throws {
        #expect(AccountsCardText(provider: try codex()).count == "1 account")
        #expect(AccountsCardText(provider: try codex([login("a", folder: "/tmp/a", madeBy: .folder)])).count == "2 accounts")
    }

    @Test
    func `should offer Codex's ways to add an account, easiest first`() throws {
        let text = AccountsCardText(provider: try codex())

        #expect(text.ways.map { $0.label } == ["Sign in with browser", "Choose Signed-in Folder"])
    }

    @Test
    func `should offer only to enter an API key for a provider the person added`() throws {
        var draft = ProviderDraftForm(start: .api)
        draft.url = "https://openrouter.ai/api/v1/auth/key"
        draft.key = .apiKey
        draft.measure = .percentUsed
        draft.used = "$.used"
        draft.name = "OpenRouter"
        let kit = try TestKit.start()
        let provider = try #require(try value(of: kit.workshop.add(draft: draft.draft, key: "")))

        #expect(AccountsCardText(provider: provider).ways.map(\.label) == ["Enter API key"])
    }

    @Test
    func `should describe, re-sign and remove an API account without mentioning a CLI or folder`() throws {
        let provider = try TestKit.start(settings: TestKit.settings("deepseek", logins: [
            TestKit.login("work", label: "Work", values: [:], madeBy: .form),
        ])).provider("deepseek")
        let text = AccountsCardText(provider: provider)
        #expect(text.defaultLoginDescription == "Default account")
        #expect(text.reauthHelp(for: provider.defaultAccount) == "Update the default account's key in Settings, then refresh.")
        #expect(text.reauthHelp(for: provider.accounts[1]) == "Remove this account and add it again with a valid key.")
        #expect(text.removeMessage(for: provider.accounts[1]) == "Removes Work from ClaudeBar and deletes its saved keys.")
    }

    @Test
    func `should show Codex's own sign-in command for a chosen folder`() throws {
        let text = AccountsCardText(provider: try codex())

        #expect(text.signInCommand(in: "/Users/me/work") == #"CODEX_HOME=/Users/me/work codex -c 'cli_auth_credentials_store="file"' login"#)
    }

    @Test
    func `should quote a folder with a space so the sign-in command works when pasted into a terminal`() throws {
        let text = AccountsCardText(provider: try codex())

        #expect(text.signInCommand(in: "/Users/me/My Work")?.hasPrefix("CODEX_HOME='/Users/me/My Work' codex") == true)
    }

    @Test
    func `should say what goes with an account when the person removes it`() throws {
        let made = "/Users/me/.claudebar/accounts/codex/\(UUID().uuidString.lowercased())"
        let provider = try codex([login("a", folder: made, madeBy: .signIn), login("b", folder: "/Users/me/codex-b", madeBy: .folder)])
        let text = AccountsCardText(provider: provider)

        #expect(text.removeMessage(for: provider.accounts[1]) == "Removes a@example.com from ClaudeBar and deletes the sign-in ClaudeBar kept for it.")
        #expect(text.removeMessage(for: provider.accounts[2]) == "Removes b@example.com from ClaudeBar. Its login and folder stay where they are.")
    }

    @Test
    func `should sign a login ClaudeBar made in again from the card, and tell the person how for one they chose`() throws {
        let made = "/Users/me/.claudebar/accounts/codex/\(UUID().uuidString.lowercased())"
        let provider = try codex([login("a", folder: made, madeBy: .signIn), login("b", folder: "/Users/me/codex-b", madeBy: .folder)])
        let text = AccountsCardText(provider: provider)

        #expect(text.reauthHelp(for: provider.accounts[1]) == nil)
        #expect(text.reauthHelp(for: provider.accounts[2]) == #"Sign in again yourself: CODEX_HOME=/Users/me/codex-b codex -c 'cli_auth_credentials_store="file"' login — then refresh."#)
    }

    @Test func `should keep a folder account's folder on removal and ask to sign in with the CLI, not for a new key`() throws {
        let json = #"{"profile":{"id":"example","name":"Example"},"cli":"example","defaultDataSource":"file","dataSources":[{"kind":"file","fetch":{"file":{"path":"/tmp/example.json"}},"mapping":{"json":{"quotas":[]}}}],"settings":[{"id":"home","label":"Home Folder","scope":"account","kind":"path"}],"accounts":{"patch":{}}}"#
        let provider = try TestKit.start(
            settings: TestKit.settings("example", logins: [TestKit.login("work", label: "Work", values: ["home": "/tmp/work profile"], madeBy: .form)]),
            custom: ["example": json]
        ).provider("example")
        let text = AccountsCardText(provider: provider)

        #expect(text.removeMessage(for: provider.accounts[1]) == "Removes Work from ClaudeBar. Its login and folder stay where they are.")
        #expect(text.reauthHelp(for: provider.accounts[1]) == "Sign in again in /tmp/work profile with your CLI, then refresh.")
    }

    @Test func `should show the provider's own sign-in hint when the default login's key is refused`() throws {
        let json = #"{"profile":{"id":"example","name":"Example"},"defaultDataSource":"api","dataSources":[{"kind":"api","credential":{"sqlite":{"path":"~/example.db","query":"SELECT 1","fields":{},"hint":"Sign in again in Example, then refresh."}},"fetch":{"http":{"url":"https://example.test"}},"mapping":{"json":{"quotas":[]}}}]}"#
        let provider = try TestKit.start(custom: ["example": json]).provider("example")

        #expect(AccountsCardText(provider: provider).reauthHelp(for: provider.defaultAccount) == "Sign in again in Example, then refresh.")
    }
}
