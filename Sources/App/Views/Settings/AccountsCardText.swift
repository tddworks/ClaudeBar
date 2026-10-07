import Foundation
import Kit

/// The words of the Accounts card, read from the provider's definition —
/// one card for every provider that can have accounts.
@MainActor
struct AccountsCardText {
    struct Way: Equatable {
        let way: AddAccountWay
        let label: String
    }

    let provider: Provider

    var count: String {
        provider.accounts.count == 1 ? "1 account" : "\(provider.accounts.count) accounts"
    }

    var defaultLoginDescription: String {
        provider.definition.cli == nil ? "Default account" : "Your \(provider.name) CLI's own login"
    }

    /// *Add Account*'s choices — what the definition says, easiest first.
    var ways: [Way] {
        (provider.definition.accounts?.ways ?? []).map { way in
            switch way {
            case .signIn: Way(way: way, label: "Sign in with browser")
            case .folder: Way(way: way, label: "Choose Signed-in Folder")
            case .form: Way(way: way, label: "Enter \(fields.first?.label ?? "Details")")
            }
        }
    }

    /// What *Add Account*'s form asks for.
    var fields: [Setting] { provider.accounts.form }

    /// The login a person runs themselves to sign in to `folder`.
    func signInCommand(in folder: String) -> String? {
        provider.definition.accounts?.signInCommand(folder: folder)
    }

    func removeMessage(for account: Account) -> String {
        if account.madeBy == .form, signedInFolder(of: account) == nil {
            return "Removes \(account.displayName) from ClaudeBar and deletes its saved keys."
        }
        if account.folder?.goesWithAccount == true {
            return "Removes \(account.displayName) from ClaudeBar and deletes the sign-in ClaudeBar kept for it."
        }
        return "Removes \(account.displayName) from ClaudeBar. Its login and folder stay where they are."
    }

    /// Whether the last refresh says the login needs signing in again.
    func needsReauth(_ account: Account) -> Bool {
        guard let tag = account.lastError?.tag else { return false }
        return tag == "sessionExpired" || tag == "authenticationRequired"
    }

    /// `nil` when the card can sign in again itself — a folder ClaudeBar
    /// made; otherwise how the person does it in their own folder.
    func reauthHelp(for account: Account) -> String? {
        if account.madeBy == .form {
            if let folder = signedInFolder(of: account) {
                return "Sign in again in \(folder) with your CLI, then refresh."
            }
            return "Remove this account and add it again with a valid key."
        }
        if account.isDefault, provider.definition.cli == nil {
            // The key lookup says how its key comes back — Cursor: the app's own login.
            return provider.configuration.keyHint ?? "Update the default account's key in Settings, then refresh."
        }
        guard let folder = account.folder, !folder.goesWithAccount else { return nil }
        guard let command = signInCommand(in: folder.path) else { return "Sign in again in \(folder.path), then refresh." }
        return "Sign in again yourself: \(command) — then refresh."
    }

    /// The folder an account made by the form signed in at — its path setting.
    private func signedInFolder(of account: Account) -> String? {
        fields.lazy.compactMap { $0.path(values: account.values) }.first
    }
}
