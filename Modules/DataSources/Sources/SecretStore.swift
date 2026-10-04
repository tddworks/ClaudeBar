import Foundation

/// The vault — keys a person gave ClaudeBar for a provider (*API KEY*). A
/// definition names a key (`"credential": { "setting": "apiKey" }`); the key
/// itself lives here, never in a definition, `settings.json`, a log line or an
/// exported file.
public protocol SecretStore: Sendable {
    /// The saved value of `name` for a provider, or `nil` when none is saved.
    func secret(_ name: String, provider: String) -> String?
}

/// The vault ClaudeBar writes to as well as reads from — a key typed into
/// *Add Account*'s form is saved here, and forgotten on *Remove*.
public protocol SecretVault: SecretStore {
    func save(_ value: String, _ name: String, provider: String)
    @discardableResult
    func delete(_ name: String, provider: String) -> Bool
}

extension SecretStore {
    /// The vault as one login sees it: every key looked up under that
    /// login's id (`deepseek.<acct>`), so an added login never reads the
    /// default login's key — and the default login, whose id is the
    /// provider's, reads exactly what it always has.
    public func scoped(to lineupId: String) -> any SecretStore {
        ScopedSecrets(base: self, lineupId: lineupId)
    }
}

private struct ScopedSecrets: SecretStore {
    let base: any SecretStore
    let lineupId: String

    func secret(_ name: String, provider: String) -> String? {
        base.secret(name, provider: lineupId)
    }
}
