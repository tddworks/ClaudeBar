import Foundation
import Domain

/// UserDefaults-based implementation of ProviderSettingsRepository and its sub-protocols.
/// Persists provider settings like isEnabled state and provider-specific configuration.
public final class UserDefaultsProviderSettingsRepository: ZaiSettingsRepository, CopilotSettingsRepository, BedrockSettingsRepository, @unchecked Sendable {
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

    // MARK: - ZaiSettingsRepository

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

    // MARK: - CopilotSettingsRepository (Configuration)

    public func copilotAuthEnvVar() -> String {
        userDefaults.string(forKey: Keys.copilotAuthEnvVar) ?? ""
    }

    public func setCopilotAuthEnvVar(_ envVar: String) {
        userDefaults.set(envVar, forKey: Keys.copilotAuthEnvVar)
    }

    // MARK: - CopilotSettingsRepository (Credentials)

    public func saveGithubToken(_ token: String) {
        userDefaults.set(token, forKey: Keys.githubToken)
    }

    public func getGithubToken() -> String? {
        userDefaults.string(forKey: Keys.githubToken)
    }

    public func deleteGithubToken() {
        userDefaults.removeObject(forKey: Keys.githubToken)
    }

    public func hasGithubToken() -> Bool {
        userDefaults.object(forKey: Keys.githubToken) != nil
    }

    public func saveGithubUsername(_ username: String) {
        userDefaults.set(username, forKey: Keys.githubUsername)
    }

    public func getGithubUsername() -> String? {
        userDefaults.string(forKey: Keys.githubUsername)
    }

    public func deleteGithubUsername() {
        userDefaults.removeObject(forKey: Keys.githubUsername)
    }

    // MARK: - BedrockSettingsRepository

    public func awsProfileName() -> String {
        userDefaults.string(forKey: Keys.awsProfileName) ?? ""
    }

    public func setAWSProfileName(_ name: String) {
        userDefaults.set(name, forKey: Keys.awsProfileName)
    }

    public func bedrockRegions() -> [String] {
        userDefaults.stringArray(forKey: Keys.bedrockRegions) ?? ["us-east-1"]
    }

    public func setBedrockRegions(_ regions: [String]) {
        userDefaults.set(regions, forKey: Keys.bedrockRegions)
    }

    public func bedrockDailyBudget() -> Decimal? {
        guard let doubleValue = userDefaults.object(forKey: Keys.bedrockDailyBudget) as? Double else {
            return nil
        }
        return Decimal(doubleValue)
    }

    public func setBedrockDailyBudget(_ amount: Decimal?) {
        if let amount {
            userDefaults.set(NSDecimalNumber(decimal: amount).doubleValue, forKey: Keys.bedrockDailyBudget)
        } else {
            userDefaults.removeObject(forKey: Keys.bedrockDailyBudget)
        }
    }

    // MARK: - Keys

    private enum Keys {
        static let zaiConfigPath = "providerConfig.zaiConfigPath"
        static let glmAuthEnvVar = "providerConfig.glmAuthEnvVar"
        static let copilotAuthEnvVar = "providerConfig.copilotAuthEnvVar"
        // Bedrock settings
        static let awsProfileName = "providerConfig.awsProfileName"
        static let bedrockRegions = "providerConfig.bedrockRegions"
        static let bedrockDailyBudget = "providerConfig.bedrockDailyBudget"
        // Credentials (kept compatible with old UserDefaultsCredentialRepository keys)
        static let githubToken = "com.claudebar.credentials.github-copilot-token"
        static let githubUsername = "com.claudebar.credentials.github-username"
    }

    /// Generates the UserDefaults key for a provider's enabled state
    private static func enabledKey(forProvider id: String) -> String {
        "provider.\(id).isEnabled"
    }
}
