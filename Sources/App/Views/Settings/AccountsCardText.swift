import Foundation
import Providers
import Quotas

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
    var fields: [Setting] { provider.accountForm }

    /// The login a person runs themselves to sign in to `folder`.
    func signInCommand(in folder: String) -> String? {
        guard let call = provider.definition.accounts?.signIn else { return nil }
        return (["\(call.homeVariable)=\(Self.shellQuoted(folder))", call.cli] + call.args.map(Self.shellQuoted)).joined(separator: " ")
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
        guard let tag = (account.lastError as? UsageError)?.tag else { return false }
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
            return provider.keyHint ?? "Update the default account's key in Settings, then refresh."
        }
        guard let folder = account.folder, !folder.goesWithAccount else { return nil }
        guard let command = signInCommand(in: folder.url.path) else { return "Sign in again in \(folder.url.path), then refresh." }
        return "Sign in again yourself: \(command) — then refresh."
    }

    /// As a shell needs it to arrive unchanged — so a pasted command works.
    private static func shellQuoted(_ argument: String) -> String {
        let plain = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./=:@~"))
        guard argument.unicodeScalars.contains(where: { !plain.contains($0) }) else { return argument }
        return "'" + argument.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// The folder an account made by the form signed in at — its path setting.
    private func signedInFolder(of account: Account) -> String? {
        fields.lazy.compactMap { $0.path(in: account.values) }.first
    }
}
