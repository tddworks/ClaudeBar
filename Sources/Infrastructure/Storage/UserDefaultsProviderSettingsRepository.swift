import Foundation
import Domain

/// UserDefaults-based implementation of ProviderSettingsRepository and its sub-protocols.
/// Persists provider settings like isEnabled state and provider-specific configuration.
public final class UserDefaultsProviderSettingsRepository: ZaiSettingsRepository, CopilotSettingsRepository, BedrockSettingsRepository, ClaudeSettingsRepository, @unchecked Sendable {
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

    public func copilotMonthlyLimit() -> Int? {
        guard let intValue = userDefaults.object(forKey: Keys.copilotMonthlyLimit) as? Int else {
            return nil
        }
        return intValue
    }

    public func setCopilotMonthlyLimit(_ limit: Int?) {
        if let limit {
            userDefaults.set(limit, forKey: Keys.copilotMonthlyLimit)
        } else {
            userDefaults.removeObject(forKey: Keys.copilotMonthlyLimit)
        }
    }

    public func copilotManualUsageValue() -> Double? {
        guard userDefaults.object(forKey: Keys.copilotManualUsageValue) != nil else {
            return nil
        }
        return userDefaults.double(forKey: Keys.copilotManualUsageValue)
    }

    public func setCopilotManualUsageValue(_ value: Double?) {
        if let value {
            userDefaults.set(value, forKey: Keys.copilotManualUsageValue)
        } else {
            userDefaults.removeObject(forKey: Keys.copilotManualUsageValue)
        }
    }

    public func copilotManualUsageIsPercent() -> Bool {
        userDefaults.bool(forKey: Keys.copilotManualUsageIsPercent)
    }

    public func setCopilotManualUsageIsPercent(_ isPercent: Bool) {
        userDefaults.set(isPercent, forKey: Keys.copilotManualUsageIsPercent)
    }

    public func copilotManualOverrideEnabled() -> Bool {
        userDefaults.bool(forKey: Keys.copilotManualOverrideEnabled)
    }

    public func setCopilotManualOverrideEnabled(_ enabled: Bool) {
        userDefaults.set(enabled, forKey: Keys.copilotManualOverrideEnabled)
    }

    public func copilotApiReturnedEmpty() -> Bool {
        userDefaults.bool(forKey: Keys.copilotApiReturnedEmpty)
    }

    public func setCopilotApiReturnedEmpty(_ empty: Bool) {
        userDefaults.set(empty, forKey: Keys.copilotApiReturnedEmpty)
    }

    // MARK: - CopilotSettingsRepository (Usage Period)

    public func copilotLastUsagePeriodMonth() -> Int? {
        guard userDefaults.object(forKey: Keys.copilotLastUsagePeriodMonth) != nil else {
            return nil
        }
        return userDefaults.integer(forKey: Keys.copilotLastUsagePeriodMonth)
    }

    public func copilotLastUsagePeriodYear() -> Int? {
        guard userDefaults.object(forKey: Keys.copilotLastUsagePeriodYear) != nil else {
            return nil
        }
        return userDefaults.integer(forKey: Keys.copilotLastUsagePeriodYear)
    }

    public func setCopilotLastUsagePeriod(month: Int, year: Int) {
        userDefaults.set(month, forKey: Keys.copilotLastUsagePeriodMonth)
        userDefaults.set(year, forKey: Keys.copilotLastUsagePeriodYear)
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
        // Claude settings
        static let claudeProbeMode = "providerConfig.claudeProbeMode"
        static let zaiConfigPath = "providerConfig.zaiConfigPath"
        static let glmAuthEnvVar = "providerConfig.glmAuthEnvVar"
        static let copilotAuthEnvVar = "providerConfig.copilotAuthEnvVar"
        static let copilotMonthlyLimit = "providerConfig.copilotMonthlyLimit"
        static let copilotManualUsageValue = "providerConfig.copilotManualUsageValue"
        static let copilotManualUsageIsPercent = "providerConfig.copilotManualUsageIsPercent"
        static let copilotManualOverrideEnabled = "providerConfig.copilotManualOverrideEnabled"
        static let copilotApiReturnedEmpty = "providerConfig.copilotApiReturnedEmpty"
        static let copilotLastUsagePeriodMonth = "providerConfig.copilotLastUsagePeriodMonth"
        static let copilotLastUsagePeriodYear = "providerConfig.copilotLastUsagePeriodYear"
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
