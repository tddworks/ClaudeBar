import Foundation
import Domain

/// Unified JSON-backed settings repository.
/// Implements all settings protocols: AppSettingsRepository + ProviderSettingsRepository
/// (including all sub-protocols) + HookSettingsRepository.
///
/// Backed by `JSONSettingsStore` reading/writing `~/.claudebar/settings.json`.
/// Credentials (tokens, API keys) use UserDefaults for now (Keychain migration later).
public final class JSONSettingsRepository:
    AppSettingsRepository,
    ZaiSettingsRepository,
    CopilotSettingsRepository,
    BedrockSettingsRepository,
    ClaudeSettingsRepository,
    CodexSettingsRepository,
    KimiSettingsRepository,
    MiniMaxSettingsRepository,
    AlibabaSettingsRepository,
    HookSettingsRepository,
    @unchecked Sendable
{
    /// Shared instance using the default settings file
    public static let shared = JSONSettingsRepository(store: .shared)

    private let store: JSONSettingsStore
    private let credentials: UserDefaults

    public init(store: JSONSettingsStore, credentials: UserDefaults = .standard) {
        self.store = store
        self.credentials = credentials
    }

    // MARK: - AppSettingsRepository

    public func themeMode() -> String {
        store.read(key: "app.themeMode") ?? "system"
    }

    public func setThemeMode(_ mode: String) {
        store.write(value: mode, key: "app.themeMode")
    }

    public func userHasChosenTheme() -> Bool {
        store.read(key: "app.userHasChosenTheme") ?? false
    }

    public func setUserHasChosenTheme(_ chosen: Bool) {
        store.write(value: chosen, key: "app.userHasChosenTheme")
    }

    public func usageDisplayMode() -> String {
        store.read(key: "app.usageDisplayMode") ?? "remaining"
    }

    public func setUsageDisplayMode(_ mode: String) {
        store.write(value: mode, key: "app.usageDisplayMode")
    }

    public func menuBarPercentageEnabled() -> Bool {
        store.read(key: "app.menuBarPercentageEnabled") ?? false
    }

    public func setMenuBarPercentageEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.menuBarPercentageEnabled")
    }

    public func menuBarPercentageProviderId() -> String {
        store.read(key: "app.menuBarPercentageProviderId") ?? "claude"
    }

    public func setMenuBarPercentageProviderId(_ providerId: String) {
        store.write(value: providerId, key: "app.menuBarPercentageProviderId")
    }

    public func menuBarPercentageQuotaKey() -> String {
        store.read(key: "app.menuBarPercentageQuotaKey") ?? "session"
    }

    public func setMenuBarPercentageQuotaKey(_ quotaKey: String) {
        store.write(value: quotaKey, key: "app.menuBarPercentageQuotaKey")
    }

    public func showDailyUsageCards() -> Bool {
        store.read(key: "app.showDailyUsageCards") ?? true
    }

    public func setShowDailyUsageCards(_ show: Bool) {
        store.write(value: show, key: "app.showDailyUsageCards")
    }

    public func overviewModeEnabled() -> Bool {
        store.read(key: "app.overviewModeEnabled") ?? false
    }

    public func setOverviewModeEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.overviewModeEnabled")
    }

    public func backgroundSyncEnabled() -> Bool {
        store.read(key: "app.backgroundSyncEnabled") ?? false
    }

    public func setBackgroundSyncEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.backgroundSyncEnabled")
    }

    public func backgroundSyncInterval() -> TimeInterval {
        store.read(key: "app.backgroundSyncInterval") ?? 60
    }

    public func setBackgroundSyncInterval(_ interval: TimeInterval) {
        store.write(value: interval, key: "app.backgroundSyncInterval")
    }

    public func claudeApiBudgetEnabled() -> Bool {
        store.read(key: "app.claudeApiBudgetEnabled") ?? false
    }

    public func setClaudeApiBudgetEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.claudeApiBudgetEnabled")
    }

    public func claudeApiBudget() -> Double {
        store.read(key: "app.claudeApiBudget") ?? 0
    }

    public func setClaudeApiBudget(_ amount: Double) {
        store.write(value: amount, key: "app.claudeApiBudget")
    }

    // MARK: - Burn Rate Warning

    public func burnRateWarningEnabled() -> Bool {
        store.read(key: "app.burnRateWarningEnabled") ?? false
    }

    public func setBurnRateWarningEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.burnRateWarningEnabled")
    }

    public func burnRateThreshold() -> Double {
        store.read(key: "app.burnRateThreshold") ?? 1.5
    }

    public func setBurnRateThreshold(_ threshold: Double) {
        store.write(value: threshold, key: "app.burnRateThreshold")
    }

    public func receiveBetaUpdates() -> Bool {
        store.read(key: "app.receiveBetaUpdates") ?? false
    }

    public func setReceiveBetaUpdates(_ receive: Bool) {
        store.write(value: receive, key: "app.receiveBetaUpdates")
    }

    // MARK: - ProviderSettingsRepository

    public func isEnabled(forProvider id: String, defaultValue: Bool) -> Bool {
        store.read(key: "providers.\(id).isEnabled") ?? defaultValue
    }

    public func setEnabled(_ enabled: Bool, forProvider id: String) {
        store.write(value: enabled, key: "providers.\(id).isEnabled")
    }

    public func customCardURL(forProvider id: String) -> String? {
        store.read(key: "providers.\(id).customCardURL")
    }

    public func setCustomCardURL(_ url: String?, forProvider id: String) {
        let value: Any? = (url?.isEmpty == false) ? url : nil
        store.write(value: value, key: "providers.\(id).customCardURL")
    }

    // MARK: - ClaudeSettingsRepository

    public func claudeProbeMode() -> ClaudeProbeMode {
        guard let raw: String = store.read(key: "claude.probeMode"),
              let mode = ClaudeProbeMode(rawValue: raw) else {
            return .cli
        }
        return mode
    }

    public func setClaudeProbeMode(_ mode: ClaudeProbeMode) {
        store.write(value: mode.rawValue, key: "claude.probeMode")
    }

    public func claudeCliFallbackEnabled() -> Bool {
        store.read(key: "claude.cliFallbackEnabled") ?? true
    }

    public func setClaudeCliFallbackEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "claude.cliFallbackEnabled")
    }

    // MARK: - CodexSettingsRepository

    public func codexProbeMode() -> CodexProbeMode {
        guard let raw: String = store.read(key: "codex.probeMode"),
              let mode = CodexProbeMode(rawValue: raw) else {
            return .rpc
        }
        return mode
    }

    public func setCodexProbeMode(_ mode: CodexProbeMode) {
        store.write(value: mode.rawValue, key: "codex.probeMode")
    }

    // MARK: - KimiSettingsRepository

    public func kimiProbeMode() -> KimiProbeMode {
        guard let raw: String = store.read(key: "kimi.probeMode"),
              let mode = KimiProbeMode(rawValue: raw) else {
            return .cli
        }
        return mode
    }

    public func setKimiProbeMode(_ mode: KimiProbeMode) {
        store.write(value: mode.rawValue, key: "kimi.probeMode")
    }

    // MARK: - ZaiSettingsRepository

    public func zaiConfigPath() -> String {
        store.read(key: "zai.configPath") ?? ""
    }

    public func setZaiConfigPath(_ path: String) {
        store.write(value: path, key: "zai.configPath")
    }

    public func glmAuthEnvVar() -> String {
        store.read(key: "zai.glmAuthEnvVar") ?? ""
    }

    public func setGlmAuthEnvVar(_ envVar: String) {
        store.write(value: envVar, key: "zai.glmAuthEnvVar")
    }

    // MARK: - CopilotSettingsRepository

    public func copilotProbeMode() -> CopilotProbeMode {
        guard let raw: String = store.read(key: "copilot.probeMode"),
              let mode = CopilotProbeMode(rawValue: raw) else {
            return .billing
        }
        return mode
    }

    public func setCopilotProbeMode(_ mode: CopilotProbeMode) {
        store.write(value: mode.rawValue, key: "copilot.probeMode")
    }

    public func copilotAuthEnvVar() -> String {
        store.read(key: "copilot.authEnvVar") ?? ""
    }

    public func setCopilotAuthEnvVar(_ envVar: String) {
        store.write(value: envVar, key: "copilot.authEnvVar")
    }

    public func copilotMonthlyLimit() -> Int? {
        store.read(key: "copilot.monthlyLimit")
    }

    public func setCopilotMonthlyLimit(_ limit: Int?) {
        store.write(value: limit, key: "copilot.monthlyLimit")
    }

    public func copilotManualUsageValue() -> Double? {
        store.read(key: "copilot.manualUsageValue")
    }

    public func setCopilotManualUsageValue(_ value: Double?) {
        store.write(value: value, key: "copilot.manualUsageValue")
    }

    public func copilotManualUsageIsPercent() -> Bool {
        store.read(key: "copilot.manualUsageIsPercent") ?? false
    }

    public func setCopilotManualUsageIsPercent(_ isPercent: Bool) {
        store.write(value: isPercent, key: "copilot.manualUsageIsPercent")
    }

    public func copilotManualOverrideEnabled() -> Bool {
        store.read(key: "copilot.manualOverrideEnabled") ?? false
    }

    public func setCopilotManualOverrideEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "copilot.manualOverrideEnabled")
    }

    public func copilotApiReturnedEmpty() -> Bool {
        store.read(key: "copilot.apiReturnedEmpty") ?? false
    }

    public func setCopilotApiReturnedEmpty(_ empty: Bool) {
        store.write(value: empty, key: "copilot.apiReturnedEmpty")
    }

    public func copilotLastUsagePeriodMonth() -> Int? {
        store.read(key: "copilot.lastUsagePeriodMonth")
    }

    public func copilotLastUsagePeriodYear() -> Int? {
        store.read(key: "copilot.lastUsagePeriodYear")
    }

    public func setCopilotLastUsagePeriod(month: Int, year: Int) {
        store.write(value: month, key: "copilot.lastUsagePeriodMonth")
        store.write(value: year, key: "copilot.lastUsagePeriodYear")
    }

    // Credentials (UserDefaults for now, Keychain migration later)

    public func saveGithubToken(_ token: String) {
        credentials.set(token, forKey: "com.claudebar.credentials.github-copilot-token")
    }

    public func getGithubToken() -> String? {
        credentials.string(forKey: "com.claudebar.credentials.github-copilot-token")
    }

    public func deleteGithubToken() {
        credentials.removeObject(forKey: "com.claudebar.credentials.github-copilot-token")
    }

    public func hasGithubToken() -> Bool {
        getGithubToken() != nil
    }

    public func saveGithubUsername(_ username: String) {
        credentials.set(username, forKey: "com.claudebar.credentials.github-username")
    }

    public func getGithubUsername() -> String? {
        credentials.string(forKey: "com.claudebar.credentials.github-username")
    }

    public func deleteGithubUsername() {
        credentials.removeObject(forKey: "com.claudebar.credentials.github-username")
    }

    // MARK: - BedrockSettingsRepository

    public func awsProfileName() -> String {
        store.read(key: "bedrock.awsProfile") ?? ""
    }

    public func setAWSProfileName(_ name: String) {
        store.write(value: name, key: "bedrock.awsProfile")
    }

    public func bedrockRegions() -> [String] {
        store.read(key: "bedrock.regions") ?? ["us-east-1"]
    }

    public func setBedrockRegions(_ regions: [String]) {
        store.write(value: regions, key: "bedrock.regions")
    }

    public func bedrockDailyBudget() -> Decimal? {
        guard let value: Double = store.read(key: "bedrock.dailyBudget") else { return nil }
        return Decimal(value)
    }

    public func setBedrockDailyBudget(_ amount: Decimal?) {
        if let amount = amount {
            store.write(value: NSDecimalNumber(decimal: amount).doubleValue, key: "bedrock.dailyBudget")
        } else {
            store.write(value: nil, key: "bedrock.dailyBudget")
        }
    }

    // MARK: - AlibabaSettingsRepository

    public func alibabaRegion() -> AlibabaRegion {
        guard let rawValue: String = store.read(key: "alibaba.region") else {
            return .international
        }
        return AlibabaRegion(rawValue: rawValue) ?? .international
    }

    public func setAlibabaRegion(_ region: AlibabaRegion) {
        store.write(value: region.rawValue, key: "alibaba.region")
    }

    public func alibabaCookieSource() -> AlibabaCookieSource {
        guard let rawValue: String = store.read(key: "alibaba.cookieSource") else {
            return .auto
        }
        return AlibabaCookieSource(rawValue: rawValue) ?? .auto
    }

    public func setAlibabaCookieSource(_ source: AlibabaCookieSource) {
        store.write(value: source.rawValue, key: "alibaba.cookieSource")
    }

    public func saveAlibabaManualCookie(_ cookie: String) {
        credentials.set(cookie, forKey: "com.claudebar.credentials.alibaba-manual-cookie")
    }

    public func getAlibabaManualCookie() -> String? {
        credentials.string(forKey: "com.claudebar.credentials.alibaba-manual-cookie")
    }

    public func saveAlibabaApiKey(_ key: String) {
        credentials.set(key, forKey: "com.claudebar.credentials.alibaba-api-key")
    }

    public func getAlibabaApiKey() -> String? {
        credentials.string(forKey: "com.claudebar.credentials.alibaba-api-key")
    }

    public func deleteAlibabaApiKey() {
        credentials.removeObject(forKey: "com.claudebar.credentials.alibaba-api-key")
    }

    public func hasAlibabaApiKey() -> Bool {
        credentials.object(forKey: "com.claudebar.credentials.alibaba-api-key") != nil
    }

    // MARK: - HookSettingsRepository

    public func isHookEnabled() -> Bool {
        store.read(key: "hook.enabled") ?? false
    }

    public func setHookEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "hook.enabled")
    }

    public func hookPort() -> Int {
        let port: Int = store.read(key: "hook.port") ?? Int(HookConstants.defaultPort)
        return port > 0 ? port : Int(HookConstants.defaultPort)
    }

    public func setHookPort(_ port: Int) {
        store.write(value: port, key: "hook.port")
    }

    // MARK: - MiniMaxSettingsRepository

    public func minimaxRegion() -> MiniMaxRegion {
        guard let raw: String = store.read(key: "minimax.region"),
              let region = MiniMaxRegion(rawValue: raw) else {
            return .china
        }
        return region
    }

    public func setMinimaxRegion(_ region: MiniMaxRegion) {
        store.write(value: region.rawValue, key: "minimax.region")
    }

    public func minimaxAuthEnvVar() -> String {
        store.read(key: "minimax.authEnvVar") ?? ""
    }

    public func setMinimaxAuthEnvVar(_ envVar: String) {
        store.write(value: envVar, key: "minimax.authEnvVar")
    }

    // MiniMax Credentials (UserDefaults for now)

    public func saveMinimaxApiKey(_ key: String) {
        credentials.set(key, forKey: "com.claudebar.credentials.minimax-api-key")
    }

    public func getMinimaxApiKey() -> String? {
        credentials.string(forKey: "com.claudebar.credentials.minimax-api-key")
    }

    public func deleteMinimaxApiKey() {
        credentials.removeObject(forKey: "com.claudebar.credentials.minimax-api-key")
    }

    public func hasMinimaxApiKey() -> Bool {
        getMinimaxApiKey() != nil
    }
}
