import Foundation
import Domain

/// Unified JSON-backed settings repository.
/// Implements all settings protocols: AppSettingsRepository + ProviderSettingsRepository
/// (including all sub-protocols) + HookSettingsRepository + NotifySettingsRepository.
///
/// Backed by `JSONSettingsStore` reading/writing `~/.claudebar/settings.json`.
/// Vercel and Notify! credentials use the injected secure store; legacy provider
/// credentials remain in UserDefaults pending their own migrations.
public final class JSONSettingsRepository:
    AppSettingsRepository,
    ZaiSettingsRepository,
    CopilotSettingsRepository,
    BedrockSettingsRepository,
    ClaudeSettingsRepository,
    CodexSettingsRepository,
    KimiSettingsRepository,
    MistralSettingsRepository,
    MiniMaxSettingsRepository,
    AlibabaSettingsRepository,
    VercelSettingsRepository,
    HookSettingsRepository,
    NotifySettingsRepository,
    @unchecked Sendable
{
    /// Shared instance using the default settings file
    public static let shared = JSONSettingsRepository(store: .shared)

    private let store: JSONSettingsStore
    private let credentials: UserDefaults
    private let secureCredentials: any CredentialRepository

    private var vercelCredentials: SecureCredentialMigration {
        SecureCredentialMigration(
            secureStore: secureCredentials,
            legacyStore: credentials,
            secureKey: CredentialKey.vercelApiKey,
            legacyKey: Self.legacyVercelApiKeyKey
        )
    }

    private var zaiCredentials: SecureCredentialMigration {
        SecureCredentialMigration(
            secureStore: secureCredentials,
            legacyStore: credentials,
            secureKey: CredentialKey.zaiApiKey,
            legacyKey: Self.legacyZaiApiKeyKey
        )
    }

    public init(
        store: JSONSettingsStore,
        credentials: UserDefaults = .standard,
        secureCredentials: any CredentialRepository = KeychainCredentialRepository.shared
    ) {
        self.store = store
        self.credentials = credentials
        self.secureCredentials = secureCredentials
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

    public func menuBarDurationEnabled() -> Bool {
        store.read(key: "app.menuBarDurationEnabled") ?? false
    }

    public func setMenuBarDurationEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.menuBarDurationEnabled")
    }

    public func menuBarStackedEnabled() -> Bool {
        store.read(key: "app.menuBarStackedEnabled") ?? false
    }

    public func setMenuBarStackedEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.menuBarStackedEnabled")
    }

    public func menuBarStackedSize() -> String {
        store.read(key: "app.menuBarStackedSize") ?? "small"
    }

    public func setMenuBarStackedSize(_ size: String) {
        store.write(value: size, key: "app.menuBarStackedSize")
    }

    public func menuBarPercentageProviderId() -> String {
        store.read(key: "app.menuBarPercentageProviderId") ?? "claude"
    }

    public func setMenuBarPercentageProviderId(_ providerId: String) {
        store.write(value: providerId, key: "app.menuBarPercentageProviderId")
    }

    public func menuBarAdditionalProviderIds() -> [String] {
        let stored: [String] = store.read(key: "app.menuBarAdditionalProviderIds") ?? []
        return normalizedMenuBarAdditionalProviderIds(stored)
    }

    public func setMenuBarAdditionalProviderIds(_ providerIds: [String]) {
        store.write(value: normalizedMenuBarAdditionalProviderIds(providerIds),
                    key: "app.menuBarAdditionalProviderIds")
    }

    private func normalizedMenuBarAdditionalProviderIds(_ providerIds: [String]) -> [String] {
        var seen: Set<String> = [menuBarPercentageProviderId(), ""]
        return Array(providerIds.filter { seen.insert($0).inserted }.prefix(2))
    }

    public func menuBarProviderSettings() -> [String: MenuBarProviderSettings] {
        let stored: [String: Any] = store.read(key: "app.menuBarProviderSettings") ?? [:]
        return stored.reduce(into: [:]) { result, entry in
            guard let value = entry.value as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: value),
                  let settings = try? JSONDecoder().decode(MenuBarProviderSettings.self, from: data) else { return }
            result[entry.key] = settings
        }
    }

    public func setMenuBarProviderSettings(_ settings: [String: MenuBarProviderSettings]) {
        guard let data = try? JSONEncoder().encode(settings),
              let value = try? JSONSerialization.jsonObject(with: data) else { return }
        store.write(value: value, key: "app.menuBarProviderSettings")
    }

    public func menuBarPercentageQuotaKey() -> String {
        store.read(key: "app.menuBarPercentageQuotaKey") ?? "session"
    }

    public func setMenuBarPercentageQuotaKey(_ quotaKey: String) {
        store.write(value: quotaKey, key: "app.menuBarPercentageQuotaKey")
    }

    public func menuBarSecondaryQuotaKey() -> String {
        store.read(key: "app.menuBarSecondaryQuotaKey") ?? ""
    }

    public func setMenuBarSecondaryQuotaKey(_ quotaKey: String) {
        store.write(value: quotaKey, key: "app.menuBarSecondaryQuotaKey")
    }

    public func showDailyUsageCards() -> Bool {
        store.read(key: "app.showDailyUsageCards") ?? true
    }

    public func setShowDailyUsageCards(_ show: Bool) {
        store.write(value: show, key: "app.showDailyUsageCards")
    }

    public func notchEnabled() -> Bool {
        store.read(key: "app.notchEnabled") ?? false
    }

    public func setNotchEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.notchEnabled")
    }

    public func touchBarEnabled() -> Bool {
        store.read(key: "app.touchBarEnabled") ?? true
    }

    public func setTouchBarEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.touchBarEnabled")
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
        // Default 10 min (issue #204): a power-conscious cadence for the
        // background menu-bar refresh when no interval has been persisted yet.
        store.read(key: "app.backgroundSyncInterval") ?? 600
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

    // MARK: - Status Colors

    public func statusColorOverrides() -> StatusColorOverrides {
        guard let stored: [String: Any] = store.read(key: "app.statusColorOverrides"),
              let data = try? JSONSerialization.data(withJSONObject: stored),
              let overrides = try? JSONDecoder().decode(StatusColorOverrides.self, from: data) else {
            return .none
        }
        return overrides
    }

    public func setStatusColorOverrides(_ overrides: StatusColorOverrides) {
        if overrides.isEmpty {
            store.write(value: nil, key: "app.statusColorOverrides")
            return
        }
        guard let data = try? JSONEncoder().encode(overrides),
              let value = try? JSONSerialization.jsonObject(with: data) else { return }
        store.write(value: value, key: "app.statusColorOverrides")
    }

    public func highContrastEnabled() -> Bool {
        store.read(key: "app.highContrastEnabled") ?? false
    }

    public func setHighContrastEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.highContrastEnabled")
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

    // MARK: - MistralSettingsRepository

    public func mistralProbeMode() -> MistralProbeMode {
        guard let raw: String = store.read(key: "mistral.probeMode"),
              let mode = MistralProbeMode(rawValue: raw) else {
            return .localLogs
        }
        return mode
    }

    public func setMistralProbeMode(_ mode: MistralProbeMode) {
        store.write(value: mode.rawValue, key: "mistral.probeMode")
    }

    public func mistralChatAuthEnvVar() -> String {
        store.read(key: "mistral.chatAuthEnvVar") ?? ""
    }

    public func setMistralChatAuthEnvVar(_ envVar: String) {
        store.write(value: envVar, key: "mistral.chatAuthEnvVar")
    }

    // Mistral Chat session cookie (UserDefaults for now)

    public func saveMistralChatCookie(_ cookie: String) {
        credentials.set(cookie, forKey: "com.claudebar.credentials.mistral-chat-cookie")
    }

    public func getMistralChatCookie() -> String? {
        credentials.string(forKey: "com.claudebar.credentials.mistral-chat-cookie")
    }

    public func deleteMistralChatCookie() {
        credentials.removeObject(forKey: "com.claudebar.credentials.mistral-chat-cookie")
    }

    public func hasMistralChatCookie() -> Bool {
        getMistralChatCookie() != nil
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

    // Z.ai Credentials (Keychain with legacy UserDefaults migration)

    public func saveZaiApiKey(_ key: String) {
        zaiCredentials.save(key)
    }

    public func getZaiApiKey() -> String? {
        zaiCredentials.get()
    }

    public func deleteZaiApiKey() {
        zaiCredentials.delete()
    }

    public func hasZaiApiKey() -> Bool {
        zaiCredentials.exists()
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

    // MARK: - NotifySettingsRepository

    public func isNotifyEnabled() -> Bool {
        store.read(key: "notify.enabled") ?? NotifyConstants.defaultEnabled
    }

    public func setNotifyEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "notify.enabled")
    }

    public func notifyDeviceId() -> String {
        store.read(key: "notify.deviceId") ?? ""
    }

    public func setNotifyDeviceId(_ deviceId: String) {
        store.write(value: deviceId, key: "notify.deviceId")
    }

    // Notify! device token: straight to the secure store, with no
    // `SecureCredentialMigration` wrapper. That wrapper exists to rescue a
    // plaintext UserDefaults value shipped by an earlier release, and Notify! has
    // never had one, so there is nothing to migrate away from.

    public func saveNotifyDeviceToken(_ token: String) {
        // Tokens arrive pasted, so they arrive with stray whitespace. An empty
        // field is the user clearing the link rather than a request to store a
        // blank secret, which would look linked and then fail with a 403.
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            deleteNotifyDeviceToken()
            return
        }
        secureCredentials.save(trimmed, forKey: CredentialKey.notifyDeviceToken)

        // Prove it landed, rather than assume. `CredentialRepository.save` has no
        // way to report a refusal, and the Keychain does refuse: a locally built
        // ClaudeBar is ad-hoc signed (`CODE_SIGN_IDENTITY` is "-"), so it has no
        // stable identity for a Keychain item's access control to name, and both
        // the read and the write come back errSecAuthFailed (-25293). A release
        // build signed with a Developer ID is unaffected. Without this check the
        // user presses Save, every call reports success, and nothing is stored.
        if secureCredentials.get(forKey: CredentialKey.notifyDeviceToken) == trimmed {
            // Clear any earlier fallback copy, so a build that regains the
            // Keychain stops leaving a plaintext one behind.
            notifyFallbackCredentials.delete(forKey: CredentialKey.notifyDeviceToken)
            return
        }

        AppLog.credentials.warning(
            "Notify! token could not be stored in the Keychain, keeping it in the app credential store instead"
        )
        notifyFallbackCredentials.save(trimmed, forKey: CredentialKey.notifyDeviceToken)
    }

    public func notifyDeviceToken() -> String? {
        secureCredentials.get(forKey: CredentialKey.notifyDeviceToken)
            ?? notifyFallbackCredentials.get(forKey: CredentialKey.notifyDeviceToken)
    }

    public func notifyDeviceTokenIsSecure() -> Bool {
        secureCredentials.get(forKey: CredentialKey.notifyDeviceToken) != nil
    }

    /// Where the token goes when the Keychain will not take it.
    ///
    /// The same UserDefaults credential store that already holds the GitHub,
    /// MiniMax, DeepSeek and Alibaba tokens, so this is the app's existing bar
    /// rather than a new low. It is a fallback and never the first choice: a
    /// signed build stores the token in the Keychain and this store stays empty.
    private var notifyFallbackCredentials: UserDefaultsCredentialRepository {
        UserDefaultsCredentialRepository(defaults: credentials)
    }

    @discardableResult
    public func deleteNotifyDeviceToken() -> Bool {
        // Both stores, unconditionally. Removing a link has to remove it,
        // and leaving a copy in whichever store this build does not read from
        // would resurrect it the day the other one starts working.
        let secure = secureCredentials.delete(forKey: CredentialKey.notifyDeviceToken)
        let fallback = notifyFallbackCredentials.delete(forKey: CredentialKey.notifyDeviceToken)
        return secure && fallback
    }

    public func hasNotifyDeviceToken() -> Bool {
        notifyDeviceToken() != nil
    }

    public func isNotifyLiveActivityEnabled() -> Bool {
        store.read(key: "notify.liveActivityEnabled") ?? NotifyConstants.defaultLiveActivityEnabled
    }

    public func setNotifyLiveActivityEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "notify.liveActivityEnabled")
    }

    public func isNotifyWidgetEnabled() -> Bool {
        store.read(key: "notify.widgetEnabled") ?? NotifyConstants.defaultWidgetEnabled
    }

    public func setNotifyWidgetEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "notify.widgetEnabled")
    }

    public func isNotifyScreenWidgetEnabled() -> Bool {
        store.read(key: "notify.screenWidgetEnabled") ?? NotifyConstants.defaultScreenWidgetEnabled
    }

    public func setNotifyScreenWidgetEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "notify.screenWidgetEnabled")
    }

    public func notifyGaugeProviderId() -> String {
        store.read(key: "notify.gauge.providerId") ?? ""
    }

    public func setNotifyGaugeProviderId(_ providerId: String) {
        store.write(value: providerId, key: "notify.gauge.providerId")
    }

    public func notifyGaugeQuotaKey() -> String {
        store.read(key: "notify.gauge.quotaKey") ?? ""
    }

    public func setNotifyGaugeQuotaKey(_ quotaKey: String) {
        store.write(value: quotaKey, key: "notify.gauge.quotaKey")
    }

    public func notifyActivityId() -> String? {
        store.read(key: "notify.activityId")
    }

    /// The optional is passed through untouched: `JSONSettingsStore.write` removes
    /// the key when the value is nil, and removal is exactly what forgetting a tile
    /// has to mean. A stored empty string would read back as a handle and send every
    /// later update to a tile that no longer exists.
    public func setNotifyActivityId(_ activityId: String?) {
        store.write(value: activityId, key: "notify.activityId")
    }

    public func notifyWidgetId() -> String? {
        store.read(key: "notify.widgetId")
    }

    /// Passed through for the same reason as the activity handle above.
    public func setNotifyWidgetId(_ widgetId: String?) {
        store.write(value: widgetId, key: "notify.widgetId")
    }

    public func notifyScreenWidgetId() -> String? {
        store.read(key: "notify.screenWidgetId")
    }

    /// Passed through for the same reason as the two handles above.
    public func setNotifyScreenWidgetId(_ screenWidgetId: String?) {
        store.write(value: screenWidgetId, key: "notify.screenWidgetId")
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

    // MARK: - VercelSettingsRepository

    public func vercelAuthEnvVar() -> String {
        store.read(key: "vercel.authEnvVar") ?? ""
    }

    public func setVercelAuthEnvVar(_ envVar: String) {
        store.write(value: envVar, key: "vercel.authEnvVar")
    }

    public func saveVercelApiKey(_ key: String) {
        vercelCredentials.save(key)
    }

    public func getVercelApiKey() -> String? {
        vercelCredentials.get()
    }

    @discardableResult
    public func deleteVercelApiKey() -> Bool {
        vercelCredentials.delete()
    }

    public func hasVercelApiKey() -> Bool {
        vercelCredentials.exists()
    }

    private static let legacyVercelApiKeyKey = "com.claudebar.credentials.vercel-api-key"
    private static let legacyZaiApiKeyKey = "com.claudebar.credentials.zai-api-key"
}

// MARK: - DeepSeekSettingsRepository

extension JSONSettingsRepository: DeepSeekSettingsRepository {
    public func deepseekAuthEnvVar() -> String {
        store.read(key: "deepseek.authEnvVar") ?? ""
    }

    public func setDeepSeekAuthEnvVar(_ envVar: String) {
        store.write(value: envVar, key: "deepseek.authEnvVar")
    }

    // DeepSeek Credentials (UserDefaults for now)

    public func saveDeepSeekApiKey(_ key: String) {
        credentials.set(key, forKey: "com.claudebar.credentials.deepseek-api-key")
    }

    public func getDeepSeekApiKey() -> String? {
        credentials.string(forKey: "com.claudebar.credentials.deepseek-api-key")
    }

    public func deleteDeepSeekApiKey() {
        credentials.removeObject(forKey: "com.claudebar.credentials.deepseek-api-key")
    }

    public func hasDeepSeekApiKey() -> Bool {
        getDeepSeekApiKey() != nil
    }
}

// MARK: - MultiAccountSettingsRepository

extension JSONSettingsRepository: MultiAccountSettingsRepository {

    public func accounts(forProvider id: String) -> [ProviderAccountConfig] {
        guard let raw: [Any] = store.read(key: Self.accountsKey(id)) else { return [] }
        return raw.compactMap(Self.decodeAccount)
    }

    public func addAccount(_ config: ProviderAccountConfig, forProvider id: String) {
        var configs = accounts(forProvider: id)
        if let index = configs.firstIndex(where: { $0.accountId == config.accountId }) {
            configs[index] = config
        } else {
            configs.append(config)
        }
        writeAccounts(configs, forProvider: id)
    }

    public func removeAccount(accountId: String, forProvider id: String) {
        let remaining = accounts(forProvider: id).filter { $0.accountId != accountId }
        writeAccounts(remaining, forProvider: id)

        // The active pointer must not outlive the account it points at.
        if activeAccountId(forProvider: id) == accountId {
            setActiveAccountId(nil, forProvider: id)
        }
    }

    public func updateAccount(_ config: ProviderAccountConfig, forProvider id: String) {
        var configs = accounts(forProvider: id)
        guard let index = configs.firstIndex(where: { $0.accountId == config.accountId }) else { return }
        configs[index] = config
        writeAccounts(configs, forProvider: id)
    }

    public func activeAccountId(forProvider id: String) -> String? {
        store.read(key: Self.activeAccountKey(id))
    }

    public func setActiveAccountId(_ accountId: String?, forProvider id: String) {
        store.write(value: accountId, key: Self.activeAccountKey(id))
    }

    // MARK: Storage helpers

    private static func accountsKey(_ id: String) -> String { "providers.\(id).accounts" }
    private static func activeAccountKey(_ id: String) -> String { "providers.\(id).activeAccountId" }

    private func writeAccounts(_ configs: [ProviderAccountConfig], forProvider id: String) {
        // Persist an empty list as a removal so the file stays free of empty arrays,
        // which keeps `accounts(forProvider:)` on its single-account path.
        let value = configs.isEmpty ? nil : configs.compactMap(Self.encodeAccount)
        store.write(value: value, key: Self.accountsKey(id))
    }

    /// `JSONSettingsStore` persists via `JSONSerialization`, so configs travel as
    /// plain dictionaries rather than as `Codable` values.
    private static func encodeAccount(_ config: ProviderAccountConfig) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(config),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private static func decodeAccount(_ raw: Any) -> ProviderAccountConfig? {
        guard let object = raw as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: object),
              let config = try? JSONDecoder().decode(ProviderAccountConfig.self, from: data) else {
            return nil
        }
        return config
    }
}
