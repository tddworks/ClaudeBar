import DataSources
import Kit
import Foundation
import Observation
import Quotas

/// *The provider's Settings page* — its DATA SOURCE (which one, its
/// fallback), its settings form's values and its CLI location (TARGET
/// §2.1).
///
/// It owns what it decides and knows no one above it: not the provider, not
/// a login. It answers what a login runs (`sources(for:isDefault:)`), and
/// every change that alters that grows `revision` — the provider pulls, and
/// remakes a login's data sources when they are older.
@MainActor
@Observable
public final class Configuration {
    @ObservationIgnored private let definition: ProviderDefinition
    @ObservationIgnored private let settings: any ProviderSettingsRepository
    @ObservationIgnored let vault: (any SecretVault)?
    @ObservationIgnored let paths: any PathChecking
    @ObservationIgnored private let isExecutable: @Sendable (String) -> Bool
    @ObservationIgnored private let locate: @Sendable (String) -> String?

    /// Grows on every change a login's data sources are made from.
    public private(set) var revision = 0
    /// *CLI location* — where this provider's CLI lives on this Mac, when the
    /// person chose one (#210). `nil` finds it as usual.
    public private(set) var cliPath: String?
    /// The definition as it runs here: the CLI at the person's location.
    private(set) var running: ProviderDefinition

    init(definition: ProviderDefinition, settings: any ProviderSettingsRepository, vault: (any SecretVault)?,
         paths: any PathChecking, isExecutable: @escaping @Sendable (String) -> Bool,
         locate: @escaping @Sendable (String) -> String?) {
        self.definition = definition
        self.settings = settings
        self.vault = vault
        self.paths = paths
        self.isExecutable = isExecutable
        self.locate = locate
        let cliPath = settings.cliPath(forProvider: definition.id)
        self.cliPath = cliPath
        self.running = definition
        do {
            self.running = try definition.runningCLI(cliPath ?? installedCLI() ?? "")
        } catch {
            AppLog.providers.error("\(definition.id): can't run the CLI at the saved location: \(error.localizedDescription)")
            self.running = definition
        }
    }

    private var id: String { definition.id }
    private var name: String { definition.profile.name }

    // MARK: - DATA SOURCE — one choice for every login

    /// The data source in use: the one the person picked, else the default.
    public var activeKind: String {
        if let chosen = settings.dataSourceKind(forProvider: id), definition.dataSource(chosen) != nil {
            return chosen
        }
        return definition.defaultDataSource
    }

    /// Switches the data source. `false` when the provider has no such one.
    @discardableResult
    public func use(_ kind: String) -> Bool {
        guard definition.dataSource(kind) != nil else { return false }
        settings.setDataSourceKind(kind, forProvider: id)
        return true
    }

    /// Whether a data source's fallback is on — a fallback the definition
    /// lets the person turn off (`enabledBySetting`) reads that setting; any
    /// other fallback is always on. `false` when there is no fallback.
    public func isFallbackEnabled(from kind: String) -> Bool {
        guard let fallback = definition.dataSource(kind)?.fallback else { return false }
        guard let setting = fallback.enabledBySetting else { return true }
        return settings.isOn(setting, forProvider: id) != false
    }

    /// Turns a switchable fallback on or off; does nothing for one that isn't.
    public func setFallbackEnabled(_ on: Bool, from kind: String) {
        guard let setting = definition.dataSource(kind)?.fallback?.enabledBySetting else { return }
        settings.setOn(on, setting, forProvider: id)
    }

    /// What to do when the active data source's key lookup finds no key —
    /// the lookup's own hint, when it has one.
    public var keyHint: String? {
        definition.dataSource(activeKind)?.credential?.hint
    }

    // MARK: - The settings form — REGION, API KEY, ENV VAR …

    /// What a setting holds for a login with these own values (the plain
    /// login has none): its own value for an account-scope one, else the
    /// provider's saved value, else its default. Never a secret's.
    public func value(of setting: Setting, ownValues values: [String: String]) -> String? {
        let value = setting.value(from: setting.ownValue(in: values) ?? settings.value(setting.id, forProvider: id))
        return value.isEmpty ? nil : value
    }

    /// Whether a value of this setting is saved for a login — a key in the
    /// vault under its id, or a value of its own (`nil` own values: the plain
    /// login, whose values are the provider's) — never the value itself.
    public func hasSaved(_ setting: Setting, login: String, ownValues values: [String: String]?) -> Bool {
        if vault?.secret(setting.id, provider: login) != nil { return true }
        let own = values.map { $0[setting.id] } ?? settings.value(setting.id, forProvider: id)
        return own != nil
    }

    /// Fills in a provider-scope setting — or the plain login's value of an
    /// account-scope one — for every login from the next refresh. A secret
    /// goes to the vault; `nil` or empty forgets it.
    public func set(_ setting: String, to value: String?) throws {
        guard let found = definition.setting(setting) else {
            throw UsageError.executionFailed("\(name) has no setting \(setting).")
        }
        let value = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        let kept = (value?.isEmpty ?? true) ? nil : value
        if let kept, let problem = found.check(kept, paths: paths) {
            throw UsageError.executionFailed(problem)
        }
        var entry = SettingEntry()
        if let kept { found.keep(kept, in: &entry, paths: paths) }
        guard entry.secrets.isEmpty || vault != nil else {
            throw UsageError.executionFailed("ClaudeBar can't keep this key securely here.")
        }
        settings.setValue(entry.values[setting], setting, forProvider: id)
        if entry.secrets.isEmpty {
            vault?.delete(setting, provider: id)
        } else {
            try keep(entry.secrets, for: id)
        }
        revision += 1
    }

    /// Saves keys in the vault under a login, reading each back: an ad-hoc
    /// build's Keychain can seem to save and keep nothing. On a refusal every
    /// key goes back to what it was — a key being replaced is never lost.
    func keep(_ secrets: [String: String], for login: String) throws {
        let before = secrets.keys.reduce(into: [String: String?]()) { $0[$1] = vault?.secret($1, provider: login) }
        for (name, value) in secrets {
            vault?.save(value, name, provider: login)
            guard vault?.secret(name, provider: login) == value else {
                for (name, previous) in before {
                    vault?.delete(name, provider: login)
                    if let previous { vault?.save(previous, name, provider: login) }
                }
                throw UsageError.executionFailed("ClaudeBar couldn't keep this key securely.")
            }
        }
    }

    // MARK: - CLI location

    /// Where the CLI is when the person chose no location: on the PATH, or
    /// else the first other place in `cli` that is a program. The PATH is
    /// asked only when such a place exists, so most launches never ask it.
    private func installedCLI() -> String? {
        guard let name = definition.cli,
              let place = definition.cliPlaces.map(paths.expanded).first(where: isExecutable),
              locate(name) == nil else { return nil }
        return place
    }

    /// Runs this provider's CLI from `path` for every login and for Add
    /// Account's sign-in, saved and in effect at once. Empty goes back to
    /// finding the CLI as usual. A path that isn't a program is refused, and
    /// nothing changes.
    public func setCLIPath(_ path: String?) throws {
        let trimmed = (path ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let chosen = trimmed.isEmpty ? nil : NSString(string: trimmed).expandingTildeInPath
        if let chosen, !isExecutable(chosen) {
            throw UsageError.executionFailed("\(chosen) isn't a program ClaudeBar can run. Choose the \(definition.cli ?? name) executable itself.")
        }
        running = try definition.runningCLI(chosen ?? installedCLI() ?? "")
        cliPath = chosen
        settings.setCLIPath(chosen, forProvider: id)
        revision += 1
    }

    // MARK: - What a login runs

    /// The definition as the plain login runs it — the CLI at its chosen
    /// location and every `{{setting.x}}` filled — so Settings prints
    /// `$MINIMAX_API_KEY`, not the template.
    public var definitionAsRun: ProviderDefinition {
        let sources = (try? sources(for: [:], isDefault: true)) ?? running.dataSources
        return ProviderDefinition(profile: running.profile, cli: running.cli, enabledByDefault: running.enabledByDefault,
                                  dataSources: sources, defaultDataSource: running.defaultDataSource, together: running.together,
                                  accounts: running.accounts, settings: running.settings, usageHistory: running.usageHistory,
                                  setup: running.setup)
    }

    /// A login's data sources as data: an added one's patched and filled
    /// with its values, then every login's settings filled in.
    func sources(for values: [String: String], isDefault: Bool) throws -> [DataSourceDefinition] {
        let sources = isDefault ? running.dataSources : try running.dataSources(forAccount: values)
        let fills = settingFills(ownValues: isDefault ? [:] : values)
        guard !fills.isEmpty else { return sources }
        return try sources.map { try $0.filled(fills, scope: "setting") }
    }

    /// Every `{{setting.x}}` a login's data sources are filled with.
    public func settingFills(ownValues values: [String: String]) -> [String: String] {
        definition.settings.reduce(into: [:]) { fills, setting in
            fills.merge(setting.fills(for: value(of: setting, ownValues: values))) { _, new in new }
        }
    }
}
