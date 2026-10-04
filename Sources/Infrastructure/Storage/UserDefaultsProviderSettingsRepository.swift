import Foundation
import Domain

/// Legacy/test UserDefaults implementation of provider settings protocols.
/// Production app persistence uses `JSONSettingsRepository`; this implementation
/// supports legacy migration and isolated tests with injected UserDefaults suites.
public final class UserDefaultsProviderSettingsRepository: ClaudeSettingsRepository, CodexSettingsRepository, DeepSeekSettingsRepository, HookSettingsRepository, @unchecked Sendable {
    /// Shared singleton instance
    public static let shared = UserDefaultsProviderSettingsRepository()

    /// The UserDefaults instance to use
    private let userDefaults: UserDefaults
    private let secureCredentials: any CredentialRepository


    /// Creates a repository with settings in UserDefaults and secrets in Keychain.
    /// - Parameters:
    ///   - userDefaults: The UserDefaults instance used for non-sensitive settings.
    ///   - secureCredentials: The credential store used for sensitive values.
    public init(
        userDefaults: UserDefaults = .standard,
        secureCredentials: any CredentialRepository = KeychainCredentialRepository.shared
    ) {
        self.userDefaults = userDefaults
        self.secureCredentials = secureCredentials
    }

    // MARK: - ProviderSettingsRepository

    public func isEnabled(forProvider id: String, defaultValue: Bool) -> Bool {
        let key = Self.enabledKey(forProvider: id)
        guard userDefaults.object(forKey: key) != nil else {
            return defaultValue
        }
        return userDefaults.bool(forKey: key)
    }

    /// Same key the Claude and Codex modes use (`providerConfig.<id>ProbeMode`).
    public func dataSourceKind(forProvider id: String) -> String? {
        userDefaults.string(forKey: "providerConfig.\(id)ProbeMode")
    }

    public func setDataSourceKind(_ kind: String, forProvider id: String) {
        userDefaults.set(kind, forKey: "providerConfig.\(id)ProbeMode")
    }

    public func cliPath(forProvider id: String) -> String? {
        userDefaults.string(forKey: "providerConfig.\(id).cliPath")
    }

    public func setCLIPath(_ path: String?, forProvider id: String) {
        userDefaults.set(path, forKey: "providerConfig.\(id).cliPath")
    }

    /// `providerConfig.<id><Setting>` — e.g. `providerConfig.claudeCliFallbackEnabled`.
    public func isOn(_ setting: String, forProvider id: String) -> Bool? {
        let key = "providerConfig.\(id)\(setting.prefix(1).uppercased())\(setting.dropFirst())"
        return userDefaults.object(forKey: key) as? Bool
    }

    public func setOn(_ on: Bool, _ setting: String, forProvider id: String) {
        userDefaults.set(on, forKey: "providerConfig.\(id)\(setting.prefix(1).uppercased())\(setting.dropFirst())")
    }

    /// `providerConfig.<id><Setting>` — e.g. `providerConfig.kimiRegion`.
    public func value(_ setting: String, forProvider id: String) -> String? {
        userDefaults.string(forKey: "providerConfig.\(id)\(setting.prefix(1).uppercased())\(setting.dropFirst())")
    }

    public func setValue(_ value: String?, _ setting: String, forProvider id: String) {
        userDefaults.set(value, forKey: "providerConfig.\(id)\(setting.prefix(1).uppercased())\(setting.dropFirst())")
    }

    public func setEnabled(_ enabled: Bool, forProvider id: String) {
        let key = Self.enabledKey(forProvider: id)
        userDefaults.set(enabled, forKey: key)
    }

    public func customCardURL(forProvider id: String) -> String? {
        userDefaults.string(forKey: "provider.\(id).customCardURL")
    }

    public func setCustomCardURL(_ url: String?, forProvider id: String) {
        if let url, !url.isEmpty {
            userDefaults.set(url, forKey: "provider.\(id).customCardURL")
        } else {
            userDefaults.removeObject(forKey: "provider.\(id).customCardURL")
        }
    }

    public func providerOrder() -> [String] {
        userDefaults.stringArray(forKey: Keys.providerOrder) ?? []
    }

    /// An empty order removes the key: nothing stored means registration order.
    public func setProviderOrder(_ order: [String]) {
        if order.isEmpty {
            userDefaults.removeObject(forKey: Keys.providerOrder)
        } else {
            userDefaults.set(order, forKey: Keys.providerOrder)
        }
    }

    public func hiddenQuotaKeys(forProvider id: String) -> Set<String> {
        Set(userDefaults.stringArray(forKey: Self.hiddenQuotaKeysKey(forProvider: id)) ?? [])
    }

    public func setHiddenQuotaKeys(_ keys: Set<String>, forProvider id: String) {
        let key = Self.hiddenQuotaKeysKey(forProvider: id)
        if keys.isEmpty {
            userDefaults.removeObject(forKey: key)
        } else {
            userDefaults.set(keys.sorted(), forKey: key)
        }
    }

    // MARK: - ClaudeSettingsRepository

    public func claudeProbeMode() -> ClaudeProbeMode {
        guard let rawValue = userDefaults.string(forKey: Keys.claudeProbeMode) else {
            return .cli // Default to CLI mode
        }
        return ClaudeProbeMode(rawValue: rawValue) ?? .cli
    }

    public func setClaudeProbeMode(_ mode: ClaudeProbeMode) {
        userDefaults.set(mode.rawValue, forKey: Keys.claudeProbeMode)
    }

    public func claudeCliFallbackEnabled() -> Bool {
        userDefaults.object(forKey: Keys.claudeCliFallbackEnabled) as? Bool ?? true
    }

    public func setClaudeCliFallbackEnabled(_ enabled: Bool) {
        userDefaults.set(enabled, forKey: Keys.claudeCliFallbackEnabled)
    }

    // MARK: - CodexSettingsRepository

    public func codexProbeMode() -> CodexProbeMode {
        guard let rawValue = userDefaults.string(forKey: Keys.codexProbeMode) else {
            return .rpc // Default to RPC mode
        }
        return CodexProbeMode(rawValue: rawValue) ?? .rpc
    }

    public func setCodexProbeMode(_ mode: CodexProbeMode) {
        userDefaults.set(mode.rawValue, forKey: Keys.codexProbeMode)
    }

    public func codexVerifiedAtLeastOnce() -> Bool {
        userDefaults.object(forKey: Keys.codexVerifiedAtLeastOnce) as? Bool ?? false
    }

    public func setCodexVerifiedAtLeastOnce(_ verified: Bool) {
        userDefaults.set(verified, forKey: Keys.codexVerifiedAtLeastOnce)
    }

    // MARK: - DeepSeekSettingsRepository

    public func deepseekAuthEnvVar() -> String {
        userDefaults.string(forKey: Keys.deepseekAuthEnvVar) ?? ""
    }

    public func setDeepSeekAuthEnvVar(_ envVar: String) {
        userDefaults.set(envVar, forKey: Keys.deepseekAuthEnvVar)
    }

    public func saveDeepSeekApiKey(_ key: String) {
        userDefaults.set(key, forKey: Keys.deepseekApiKey)
    }

    public func getDeepSeekApiKey() -> String? {
        userDefaults.string(forKey: Keys.deepseekApiKey)
    }

    public func deleteDeepSeekApiKey() {
        userDefaults.removeObject(forKey: Keys.deepseekApiKey)
    }

    public func hasDeepSeekApiKey() -> Bool {
        userDefaults.object(forKey: Keys.deepseekApiKey) != nil
    }

    // MARK: - HookSettingsRepository

    public func isHookEnabled() -> Bool {
        guard userDefaults.object(forKey: Keys.hookEnabled) != nil else {
            return false
        }
        return userDefaults.bool(forKey: Keys.hookEnabled)
    }

    public func setHookEnabled(_ enabled: Bool) {
        userDefaults.set(enabled, forKey: Keys.hookEnabled)
    }

    public func hookPort() -> Int {
        let port = userDefaults.integer(forKey: Keys.hookPort)
        return port > 0 ? port : Int(HookConstants.defaultPort)
    }

    public func setHookPort(_ port: Int) {
        userDefaults.set(port, forKey: Keys.hookPort)
    }

    // MARK: - Keys

    private enum Keys {
        // Hook settings
        static let hookEnabled = "hookConfig.enabled"
        static let hookPort = "hookConfig.port"
        // Claude settings
        static let claudeProbeMode = "providerConfig.claudeProbeMode"
        static let claudeCliFallbackEnabled = "providerConfig.claudeCliFallbackEnabled"
        // Provider display order (issue #141)
        static let providerOrder = "providerConfig.providerOrder"
        // Codex settings
        static let codexProbeMode = "providerConfig.codexProbeMode"
        static let codexVerifiedAtLeastOnce = "providerConfig.codexVerifiedAtLeastOnce"
        // DeepSeek settings
        static let deepseekAuthEnvVar = "providerConfig.deepseekAuthEnvVar"
        static let deepseekApiKey = "com.claudebar.credentials.deepseek-api-key"
        // Credentials (kept compatible with old UserDefaultsCredentialRepository keys)
    }

    /// Generates the UserDefaults key for a provider's enabled state
    private static func enabledKey(forProvider id: String) -> String {
        "provider.\(id).isEnabled"
    }

    /// Generates the UserDefaults key for a provider's hidden quota keys
    private static func hiddenQuotaKeysKey(forProvider id: String) -> String {
        "provider.\(id).hiddenQuotaKeys"
    }
}

// MARK: - MultiAccountSettingsRepository

extension UserDefaultsProviderSettingsRepository: MultiAccountSettingsRepository {
    public func accounts(forProvider id: String) -> [ProviderAccountConfig] {
        guard let data = userDefaults.data(forKey: Self.accountsKey(id)) else { return [] }
        return (try? JSONDecoder().decode([ProviderAccountConfig].self, from: data)) ?? []
    }

    public func addAccount(_ config: ProviderAccountConfig, forProvider id: String) {
        writeAccounts(accounts(forProvider: id).filter { $0.accountId != config.accountId } + [config], forProvider: id)
    }

    public func removeAccount(accountId: String, forProvider id: String) {
        writeAccounts(accounts(forProvider: id).filter { $0.accountId != accountId }, forProvider: id)
    }

    public func updateAccount(_ config: ProviderAccountConfig, forProvider id: String) {
        writeAccounts(accounts(forProvider: id).map { $0.accountId == config.accountId ? config : $0 }, forProvider: id)
    }

    public func defaultAccountLabel(forProvider id: String) -> String? {
        userDefaults.string(forKey: "providerConfig.\(id).defaultAccountLabel")
    }

    public func setDefaultAccountLabel(_ label: String?, forProvider id: String) {
        userDefaults.set(label, forKey: "providerConfig.\(id).defaultAccountLabel")
    }

    public func accountOrder(forProvider id: String) -> [String] {
        userDefaults.stringArray(forKey: "providerConfig.\(id).accountOrder") ?? []
    }

    public func setAccountOrder(_ accountIds: [String], forProvider id: String) {
        userDefaults.set(accountIds, forKey: "providerConfig.\(id).accountOrder")
    }

    private static func accountsKey(_ id: String) -> String { "providerConfig.\(id).accounts" }

    private func writeAccounts(_ configs: [ProviderAccountConfig], forProvider id: String) {
        userDefaults.set(try? JSONEncoder().encode(configs), forKey: Self.accountsKey(id))
    }
}
