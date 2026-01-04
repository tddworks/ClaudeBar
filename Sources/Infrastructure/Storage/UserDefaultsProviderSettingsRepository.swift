import Foundation
import Domain

/// UserDefaults-based implementation of ProviderSettingsRepository.
/// Persists provider settings like isEnabled state.
public final class UserDefaultsProviderSettingsRepository: ProviderSettingsRepository, @unchecked Sendable {
    /// Shared singleton instance
    public static let shared = UserDefaultsProviderSettingsRepository()

    /// The UserDefaults instance to use
    private let userDefaults: UserDefaults

    /// Creates a new repository with the specified UserDefaults instance
    /// - Parameter userDefaults: The UserDefaults to use (defaults to .standard)
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    // MARK: - ProviderSettingsRepository

    public func isEnabled(forProvider id: String, defaultValue: Bool) -> Bool {
        let key = Self.enabledKey(forProvider: id)
        guard userDefaults.object(forKey: key) != nil else {
            return defaultValue
        }
        return userDefaults.bool(forKey: key)
    }

    public func setEnabled(_ enabled: Bool, forProvider id: String) {
        let key = Self.enabledKey(forProvider: id)
        userDefaults.set(enabled, forKey: key)
    }

    // MARK: - Key Generation

    /// Generates the UserDefaults key for a provider's enabled state
    private static func enabledKey(forProvider id: String) -> String {
        "provider.\(id).isEnabled"
    }
}

/// UserDefaults-based implementation of ProviderConfigRepository.
/// Persists provider-specific configuration settings.
public final class UserDefaultsProviderConfigRepository: ProviderConfigRepository, @unchecked Sendable {
    /// Shared singleton instance
    public static let shared = UserDefaultsProviderConfigRepository()

    /// The UserDefaults instance to use
    private let userDefaults: UserDefaults

    /// Creates a new repository with the specified UserDefaults instance
    /// - Parameter userDefaults: The UserDefaults to use (defaults to .standard)
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    // MARK: - ProviderConfigRepository

    public func zaiConfigPath() -> String {
        userDefaults.string(forKey: Keys.zaiConfigPath) ?? ""
    }

    public func setZaiConfigPath(_ path: String) {
        userDefaults.set(path, forKey: Keys.zaiConfigPath)
    }

    public func glmAuthEnvVar() -> String {
        userDefaults.string(forKey: Keys.glmAuthEnvVar) ?? ""
    }

    public func setGlmAuthEnvVar(_ envVar: String) {
        userDefaults.set(envVar, forKey: Keys.glmAuthEnvVar)
    }

    public func copilotAuthEnvVar() -> String {
        userDefaults.string(forKey: Keys.copilotAuthEnvVar) ?? ""
    }

    public func setCopilotAuthEnvVar(_ envVar: String) {
        userDefaults.set(envVar, forKey: Keys.copilotAuthEnvVar)
    }

    // MARK: - Keys

    private enum Keys {
        static let zaiConfigPath = "providerConfig.zaiConfigPath"
        static let glmAuthEnvVar = "providerConfig.glmAuthEnvVar"
        static let copilotAuthEnvVar = "providerConfig.copilotAuthEnvVar"
    }
}
