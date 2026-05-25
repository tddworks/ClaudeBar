import Foundation
import Domain

/// UserDefaults-based implementation of ProviderSettingsRepository and its sub-protocols.
/// Persists provider settings like isEnabled state and provider-specific configuration.
public final class UserDefaultsProviderSettingsRepository: ZaiSettingsRepository, CopilotSettingsRepository, BedrockSettingsRepository, ClaudeSettingsRepository, CodexSettingsRepository, KimiSettingsRepository, MiniMaxSettingsRepository, AlibabaSettingsRepository, OllamaSettingsRepository, HookSettingsRepository, @unchecked Sendable {
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

    // MARK: - CopilotSettingsRepository (Probe Mode)

    public func copilotProbeMode() -> CopilotProbeMode {
        guard let rawValue = userDefaults.string(forKey: Keys.copilotProbeMode) else {
            return .billing // Default to Billing API mode
        }
        return CopilotProbeMode(rawValue: rawValue) ?? .billing
    }

    public func setCopilotProbeMode(_ mode: CopilotProbeMode) {
        userDefaults.set(mode.rawValue, forKey: Keys.copilotProbeMode)
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

    // MARK: - KimiSettingsRepository

    public func kimiProbeMode() -> KimiProbeMode {
        guard let rawValue = userDefaults.string(forKey: Keys.kimiProbeMode) else {
            return .cli // Default to CLI mode
        }
        return KimiProbeMode(rawValue: rawValue) ?? .cli
    }

    public func setKimiProbeMode(_ mode: KimiProbeMode) {
        userDefaults.set(mode.rawValue, forKey: Keys.kimiProbeMode)
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

    // MARK: - MiniMaxSettingsRepository

    public func minimaxRegion() -> MiniMaxRegion {
        // Legacy compatibility: key absent means user upgraded from pre-region version,
        // which only supported china (minimaxi.com). (兼容旧版：无 key 则默认中国区)
        guard let rawValue = userDefaults.string(forKey: Keys.minimaxRegion) else {
            return .china
        }
        return MiniMaxRegion(rawValue: rawValue) ?? .china
    }

    public func setMinimaxRegion(_ region: MiniMaxRegion) {
        userDefaults.set(region.rawValue, forKey: Keys.minimaxRegion)
    }

    public func minimaxAuthEnvVar() -> String {
        userDefaults.string(forKey: Keys.minimaxiAuthEnvVar) ?? ""
    }

    public func setMinimaxAuthEnvVar(_ envVar: String) {
        userDefaults.set(envVar, forKey: Keys.minimaxiAuthEnvVar)
    }

    public func saveMinimaxApiKey(_ key: String) {
        userDefaults.set(key, forKey: Keys.minimaxiApiKey)
    }

    public func getMinimaxApiKey() -> String? {
        userDefaults.string(forKey: Keys.minimaxiApiKey)
    }

    public func deleteMinimaxApiKey() {
        userDefaults.removeObject(forKey: Keys.minimaxiApiKey)
    }

    public func hasMinimaxApiKey() -> Bool {
        userDefaults.object(forKey: Keys.minimaxiApiKey) != nil
    }

    // MARK: - AlibabaSettingsRepository

    public func alibabaRegion() -> AlibabaRegion {
        guard let rawValue = userDefaults.string(forKey: Keys.alibabaRegion) else {
            return .international
        }
        return AlibabaRegion(rawValue: rawValue) ?? .international
    }

    public func setAlibabaRegion(_ region: AlibabaRegion) {
        userDefaults.set(region.rawValue, forKey: Keys.alibabaRegion)
    }

    public func alibabaCookieSource() -> AlibabaCookieSource {
        guard let rawValue = userDefaults.string(forKey: Keys.alibabaCookieSource) else {
            return .auto
        }
        return AlibabaCookieSource(rawValue: rawValue) ?? .auto
    }

    public func setAlibabaCookieSource(_ source: AlibabaCookieSource) {
        userDefaults.set(source.rawValue, forKey: Keys.alibabaCookieSource)
    }

    public func saveAlibabaManualCookie(_ cookie: String) {
        userDefaults.set(cookie, forKey: Keys.alibabaManualCookie)
    }

    public func getAlibabaManualCookie() -> String? {
        userDefaults.string(forKey: Keys.alibabaManualCookie)
    }

    public func saveAlibabaApiKey(_ key: String) {
        userDefaults.set(key, forKey: Keys.alibabaApiKey)
    }

    public func getAlibabaApiKey() -> String? {
        userDefaults.string(forKey: Keys.alibabaApiKey)
    }

    public func deleteAlibabaApiKey() {
        userDefaults.removeObject(forKey: Keys.alibabaApiKey)
    }

    public func hasAlibabaApiKey() -> Bool {
        userDefaults.object(forKey: Keys.alibabaApiKey) != nil
    }

    // MARK: - OllamaSettingsRepository

    public func ollamaProbeMode() -> OllamaProbeMode {
        guard let rawValue = userDefaults.string(forKey: Keys.ollamaProbeMode) else {
            return .api // Default to API mode (more reliable than cookie scraping)
        }
        return OllamaProbeMode(rawValue: rawValue) ?? .api
    }

    public func setOllamaProbeMode(_ mode: OllamaProbeMode) {
        userDefaults.set(mode.rawValue, forKey: Keys.ollamaProbeMode)
    }

    public func ollamaAuthEnvVar() -> String {
        userDefaults.string(forKey: Keys.ollamaAuthEnvVar) ?? ""
    }

    public func setOllamaAuthEnvVar(_ envVar: String) {
        userDefaults.set(envVar, forKey: Keys.ollamaAuthEnvVar)
    }

    public func saveOllamaApiKey(_ key: String) {
        userDefaults.set(key, forKey: Keys.ollamaApiKey)
    }

    public func getOllamaApiKey() -> String? {
        userDefaults.string(forKey: Keys.ollamaApiKey)
    }

    public func deleteOllamaApiKey() {
        userDefaults.removeObject(forKey: Keys.ollamaApiKey)
    }

    public func hasOllamaApiKey() -> Bool {
        userDefaults.object(forKey: Keys.ollamaApiKey) != nil
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
        // Codex settings
        static let codexProbeMode = "providerConfig.codexProbeMode"
        // Kimi settings
        static let kimiProbeMode = "providerConfig.kimiProbeMode"
        static let zaiConfigPath = "providerConfig.zaiConfigPath"
        static let glmAuthEnvVar = "providerConfig.glmAuthEnvVar"
        static let copilotProbeMode = "providerConfig.copilotProbeMode"
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
        // MiniMax settings (key strings kept for backward compatibility 保持向后兼容)
        static let minimaxRegion = "providerConfig.minimaxRegion"
        static let minimaxiAuthEnvVar = "providerConfig.minimaxiAuthEnvVar"
        static let minimaxiApiKey = "com.claudebar.credentials.minimaxi-api-key"
        // Alibaba settings
        static let alibabaRegion = "providerConfig.alibabaRegion"
        static let alibabaCookieSource = "providerConfig.alibabaCookieSource"
        static let alibabaManualCookie = "com.claudebar.credentials.alibaba-manual-cookie"
        static let alibabaApiKey = "com.claudebar.credentials.alibaba-api-key"
        // Ollama settings
        static let ollamaProbeMode = "providerConfig.ollamaProbeMode"
        static let ollamaAuthEnvVar = "providerConfig.ollamaAuthEnvVar"
        static let ollamaApiKey = "com.claudebar.credentials.ollama-api-key"
        // Credentials (kept compatible with old UserDefaultsCredentialRepository keys)
        static let githubToken = "com.claudebar.credentials.github-copilot-token"
        static let githubUsername = "com.claudebar.credentials.github-username"
    }

    /// Generates the UserDefaults key for a provider's enabled state
    private static func enabledKey(forProvider id: String) -> String {
        "provider.\(id).isEnabled"
    }
}
