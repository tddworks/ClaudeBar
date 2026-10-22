import Foundation

extension CredentialLookup {
    /// The keys the person gave ClaudeBar that this lookup reads, however it
    /// is wrapped — `{ "setting": "apiKey" }` inside a `firstOf`, a refresh or
    /// a refinement.
    public var settings: [String] {
        switch self {
        case .setting(let name): [name]
        case .firstOf(let lookups): lookups.flatMap(\.settings)
        case .refreshing(let base, _), .refined(let base, _): base.settings
        case .environment, .jsonFile, .keychain, .browserCookies, .browserStorage, .sqlite: []
        }
    }
}

extension Fetch {
    /// The settings handed to what it runs as secrets — a script's keys,
    /// read from the vault, never written into the definition (#602).
    var secretSettings: [String] {
        guard case .script(let call) = self else { return [] }
        return Array(call.secrets.values)
    }
}

extension DataSourceDefinition {
    /// The setting names this data source reads: its credential's key, a key
    /// its script is handed as a secret, and every `{{setting.<name>}}` it
    /// fills in, as written (`region`, or a choice's value `region.console`).
    /// A `Setting` says which of them are its own.
    public var settingsRead: Set<String> {
        Set((credential?.settings ?? []) + fetch.secretSettings + unfilled(scope: "setting"))
    }
}
