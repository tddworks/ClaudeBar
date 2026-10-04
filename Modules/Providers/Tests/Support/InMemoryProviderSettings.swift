import Providers
import Quotas
import Foundation

/// A settings repository that keeps everything in memory — the real behaviour
/// a `Provider` relies on, without touching `~/.claudebar/settings.json`.
final class InMemoryProviderSettings: MultiAccountSettingsRepository, @unchecked Sendable {
    private var accountConfigs: [String: [ProviderAccountConfig]] = [:]
    private var defaultLabels: [String: String] = [:]
    private var enabled: [String: Bool] = [:]
    private var kinds: [String: String] = [:]
    private var cardURLs: [String: String] = [:]
    /// `"<provider>.<setting>"` → on/off, as `settings.json` keeps them.
    private var flags: [String: Bool]
    /// Quota keys hidden per provider (issue #140).
    private var hiddenKeys: [String: Set<String>] = [:]

    init(dataSourceKinds: [String: String] = [:], flags: [String: Bool] = [:]) {
        self.kinds = dataSourceKinds
        self.flags = flags
    }

    func isOn(_ setting: String, forProvider id: String) -> Bool? {
        flags["\(id).\(setting)"]
    }

    func setOn(_ on: Bool, _ setting: String, forProvider id: String) {
        flags["\(id).\(setting)"] = on
    }

    /// `"<provider>.<setting>"` → value, as `settings.json` keeps them.
    private var values: [String: String] = [:]

    func value(_ setting: String, forProvider id: String) -> String? {
        values["\(id).\(setting)"]
    }

    func setValue(_ value: String?, _ setting: String, forProvider id: String) {
        values["\(id).\(setting)"] = value
    }

    func isEnabled(forProvider id: String) -> Bool {
        enabled[id] ?? true
    }

    func isEnabled(forProvider id: String, defaultValue: Bool) -> Bool {
        enabled[id] ?? defaultValue
    }

    func setEnabled(_ enabled: Bool, forProvider id: String) {
        self.enabled[id] = enabled
    }

    func customCardURL(forProvider id: String) -> String? {
        cardURLs[id]
    }

    func setCustomCardURL(_ url: String?, forProvider id: String) {
        cardURLs[id] = url
    }

    func dataSourceKind(forProvider id: String) -> String? {
        kinds[id]
    }

    func setDataSourceKind(_ kind: String, forProvider id: String) {
        kinds[id] = kind
    }

    private var cliPaths: [String: String] = [:]

    func cliPath(forProvider id: String) -> String? {
        cliPaths[id]
    }

    func setCLIPath(_ path: String?, forProvider id: String) {
        cliPaths[id] = path
    }

    // MARK: - Accounts

    func accounts(forProvider id: String) -> [ProviderAccountConfig] {
        accountConfigs[id] ?? []
    }

    func addAccount(_ config: ProviderAccountConfig, forProvider id: String) {
        accountConfigs[id, default: []].removeAll { $0.accountId == config.accountId }
        accountConfigs[id, default: []].append(config)
    }

    func removeAccount(accountId: String, forProvider id: String) {
        accountConfigs[id]?.removeAll { $0.accountId == accountId }
    }

    func updateAccount(_ config: ProviderAccountConfig, forProvider id: String) {
        guard let index = accountConfigs[id]?.firstIndex(where: { $0.accountId == config.accountId }) else { return }
        accountConfigs[id]?[index] = config
    }

    func defaultAccountLabel(forProvider id: String) -> String? {
        defaultLabels[id]
    }

    func setDefaultAccountLabel(_ label: String?, forProvider id: String) {
        defaultLabels[id] = label
    }

    private var orders: [String: [String]] = [:]

    func accountOrder(forProvider id: String) -> [String] {
        orders[id] ?? []
    }

    func setAccountOrder(_ accountIds: [String], forProvider id: String) {
        orders[id] = accountIds
    }

    func hiddenQuotaKeys(forProvider id: String) -> Set<String> {
        hiddenKeys[id] ?? []
    }

    func setHiddenQuotaKeys(_ keys: Set<String>, forProvider id: String) {
        hiddenKeys[id] = keys
    }
}
