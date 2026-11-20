import Foundation
import DataSources
import Activity
import Storage

/// The App's own settings in `~/.claudebar/settings.json` (`app.*`): the
/// theme, the menu bar, the popover, status colours. Written through Storage's
/// `JSONSettingsStore`, the same file every module's settings are in.
final class AppSettingsFile: AppSettingsRepository, @unchecked Sendable {
    /// The person's own settings file.
    static let shared = AppSettingsFile(store: .shared)

    private let store: JSONSettingsStore
    private let vault: any SecretVault

    init(store: JSONSettingsStore, vault: any SecretVault = Storage.makeVault()) {
        self.store = store
        self.vault = vault
    }

    // MARK: - AppSettingsRepository

    func themeMode() -> String {
        store.read(key: "app.themeMode") ?? "system"
    }

    func setThemeMode(_ mode: String) {
        store.write(value: mode, key: "app.themeMode")
    }

    func themeTextStyle() -> String {
        store.read(key: "app.themeTextStyle") ?? "themed"
    }

    func setThemeTextStyle(_ style: String) {
        store.write(value: style, key: "app.themeTextStyle")
    }

    func themeRunnerShown() -> Bool {
        store.read(key: "app.themeRunner") ?? true
    }

    func setThemeRunnerShown(_ shown: Bool) {
        store.write(value: shown, key: "app.themeRunner")
    }

    func userHasChosenTheme() -> Bool {
        store.read(key: "app.userHasChosenTheme") ?? false
    }

    func setUserHasChosenTheme(_ chosen: Bool) {
        store.write(value: chosen, key: "app.userHasChosenTheme")
    }

    func usageDisplayMode() -> String {
        store.read(key: "app.usageDisplayMode") ?? "remaining"
    }

    func setUsageDisplayMode(_ mode: String) {
        store.write(value: mode, key: "app.usageDisplayMode")
    }

    func menuBarPercentageEnabled() -> Bool {
        store.read(key: "app.menuBarPercentageEnabled") ?? false
    }

    func setMenuBarPercentageEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.menuBarPercentageEnabled")
    }

    func menuBarDurationEnabled() -> Bool {
        store.read(key: "app.menuBarDurationEnabled") ?? false
    }

    func setMenuBarDurationEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.menuBarDurationEnabled")
    }

    func menuBarAccountLabelsEnabled() -> Bool {
        store.read(key: "app.menuBarAccountLabelsEnabled") ?? true
    }

    func setMenuBarAccountLabelsEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.menuBarAccountLabelsEnabled")
    }

    func menuBarProviderLogoEnabled() -> Bool {
        store.read(key: "app.menuBarProviderLogoEnabled") ?? false
    }

    func setMenuBarProviderLogoEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.menuBarProviderLogoEnabled")
    }

    func menuBarStackedEnabled() -> Bool {
        store.read(key: "app.menuBarStackedEnabled") ?? false
    }

    func setMenuBarStackedEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.menuBarStackedEnabled")
    }

    func menuBarStackedSize() -> String {
        store.read(key: "app.menuBarStackedSize") ?? "small"
    }

    func setMenuBarStackedSize(_ size: String) {
        store.write(value: size, key: "app.menuBarStackedSize")
    }

    func menuBarPercentageProviderId() -> String {
        store.read(key: "app.menuBarPercentageProviderId") ?? "claude"
    }

    func setMenuBarPercentageProviderId(_ providerId: String) {
        store.write(value: providerId, key: "app.menuBarPercentageProviderId")
    }

    func menuBarAdditionalProviderIds() -> [String] {
        let stored: [String] = store.read(key: "app.menuBarAdditionalProviderIds") ?? []
        return normalizedMenuBarAdditionalProviderIds(stored)
    }

    func setMenuBarAdditionalProviderIds(_ providerIds: [String]) {
        store.write(value: normalizedMenuBarAdditionalProviderIds(providerIds),
                    key: "app.menuBarAdditionalProviderIds")
    }

    private func normalizedMenuBarAdditionalProviderIds(_ providerIds: [String]) -> [String] {
        var seen: Set<String> = [menuBarPercentageProviderId(), ""]
        return Array(providerIds.filter { seen.insert($0).inserted }.prefix(2))
    }

    func menuBarProviderSettings() -> [String: MenuBarProviderSettings] {
        let stored: [String: Any] = store.read(key: "app.menuBarProviderSettings") ?? [:]
        return stored.reduce(into: [:]) { result, entry in
            guard let value = entry.value as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: value),
                  let settings = try? JSONDecoder().decode(MenuBarProviderSettings.self, from: data) else { return }
            result[entry.key] = settings
        }
    }

    func setMenuBarProviderSettings(_ settings: [String: MenuBarProviderSettings]) {
        guard let data = try? JSONEncoder().encode(settings),
              let value = try? JSONSerialization.jsonObject(with: data) else { return }
        store.write(value: value, key: "app.menuBarProviderSettings")
    }

    func menuBarPercentageQuotaKey() -> String {
        store.read(key: "app.menuBarPercentageQuotaKey") ?? "session"
    }

    func setMenuBarPercentageQuotaKey(_ quotaKey: String) {
        store.write(value: quotaKey, key: "app.menuBarPercentageQuotaKey")
    }

    func menuBarSecondaryQuotaKey() -> String {
        store.read(key: "app.menuBarSecondaryQuotaKey") ?? ""
    }

    func setMenuBarSecondaryQuotaKey(_ quotaKey: String) {
        store.write(value: quotaKey, key: "app.menuBarSecondaryQuotaKey")
    }

    /// `app.usageSections.<section>`. Unset, it is the section's default —
    /// unless the person had turned the one old switch, *Daily Usage Cards*
    /// (`app.showDailyUsageCards`), off: then every section stays hidden.
    func isShown(_ section: UsageSection) -> Bool {
        if let shown: Bool = store.read(key: "app.usageSections.\(section.rawValue)") { return shown }
        let dailyUsageCards: Bool? = store.read(key: "app.showDailyUsageCards")
        return dailyUsageCards == false ? false : section.isShownByDefault
    }

    func setShown(_ section: UsageSection, _ shown: Bool) {
        store.write(value: shown, key: "app.usageSections.\(section.rawValue)")
    }

    func hideAccountEmail() -> Bool {
        store.read(key: "app.hideAccountEmail") ?? false
    }

    func setHideAccountEmail(_ hide: Bool) {
        store.write(value: hide, key: "app.hideAccountEmail")
    }

    func popoverTitle() -> String {
        store.read(key: "app.popoverTitle") ?? ""
    }

    func setPopoverTitle(_ title: String) {
        store.write(value: title, key: "app.popoverTitle")
    }

    func hideLeaderboardCountry() -> Bool {
        store.read(key: "app.hideLeaderboardCountry") ?? false
    }

    func setHideLeaderboardCountry(_ hide: Bool) {
        store.write(value: hide, key: "app.hideLeaderboardCountry")
    }

    func hideLeaderboardName() -> Bool {
        store.read(key: "app.hideLeaderboardName") ?? false
    }

    func setHideLeaderboardName(_ hide: Bool) {
        store.write(value: hide, key: "app.hideLeaderboardName")
    }

    func popoverTextSize() -> String {
        store.read(key: "app.popoverTextSize") ?? "medium"
    }

    func setPopoverTextSize(_ size: String) {
        store.write(value: size, key: "app.popoverTextSize")
    }

    func notchEnabled() -> Bool {
        store.read(key: "app.notchEnabled") ?? false
    }

    func setNotchEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.notchEnabled")
    }

    func notchWhenIdle() -> NotchWhenIdle {
        // Unset, or a choice from a newer build: the quota, so nobody's notch
        // goes away after updating.
        guard let saved: String = store.read(key: "app.notchWhenIdle") else { return .default }
        return NotchWhenIdle(rawValue: saved) ?? .default
    }

    func setNotchWhenIdle(_ whenIdle: NotchWhenIdle) {
        store.write(value: whenIdle.rawValue, key: "app.notchWhenIdle")
    }

    func touchBarEnabled() -> Bool {
        store.read(key: "app.touchBarEnabled") ?? true
    }

    func setTouchBarEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.touchBarEnabled")
    }

    func popoverOpensOn() -> PopoverOpensOn {
        if let saved: String = store.read(key: "app.popoverOpensOn") {
            return PopoverOpensOn(rawValue: saved) ?? .whereILeftIt
        }
        // Overview Mode, which All replaced, read once: it opened on everything.
        let hadOverviewMode: Bool = store.read(key: "app.overviewModeEnabled") ?? false
        return hadOverviewMode ? .all : .whereILeftIt
    }

    func setPopoverOpensOn(_ opensOn: PopoverOpensOn) {
        store.write(value: opensOn.rawValue, key: "app.popoverOpensOn")
    }

    func allPageStyle() -> AllPageStyle {
        // Unset, or a style from a newer build this one doesn't know: the ring
        // cards, so nobody's All page changes after updating.
        guard let saved: String = store.read(key: "app.allPageStyle") else { return AllPageStyle.default }
        return AllPageStyle(rawValue: saved) ?? AllPageStyle.default
    }

    func setAllPageStyle(_ style: AllPageStyle) {
        store.write(value: style.rawValue, key: "app.allPageStyle")
    }

    func backgroundSyncEnabled() -> Bool {
        store.read(key: "app.backgroundSyncEnabled") ?? false
    }

    func setBackgroundSyncEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.backgroundSyncEnabled")
    }

    func backgroundSyncInterval() -> TimeInterval {
        // Default 10 min (issue #204): a power-conscious cadence for the
        // background menu-bar refresh when no interval has been persisted yet.
        store.read(key: "app.backgroundSyncInterval") ?? 600
    }

    func setBackgroundSyncInterval(_ interval: TimeInterval) {
        store.write(value: interval, key: "app.backgroundSyncInterval")
    }

    func claudeApiBudgetEnabled() -> Bool {
        store.read(key: "app.claudeApiBudgetEnabled") ?? false
    }

    func setClaudeApiBudgetEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.claudeApiBudgetEnabled")
    }

    func claudeApiBudget() -> Double {
        store.read(key: "app.claudeApiBudget") ?? 0
    }

    func setClaudeApiBudget(_ amount: Double) {
        store.write(value: amount, key: "app.claudeApiBudget")
    }

    // MARK: - Refresh faster while a quota moves (#642)

    func adaptiveRefreshEnabled() -> Bool {
        store.read(key: "app.adaptiveRefreshEnabled") ?? false
    }

    func setAdaptiveRefreshEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.adaptiveRefreshEnabled")
    }

    // MARK: - Warn when a quota will run out before it resets
    //
    // `app.burnRateThreshold`, the retired multiplier, is no longer read or
    // written: an old saved value is ignored.

    func burnRateWarningEnabled() -> Bool {
        store.read(key: "app.burnRateWarningEnabled") ?? false
    }

    func setBurnRateWarningEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.burnRateWarningEnabled")
    }

    // MARK: - Status Colors

    func statusColorOverrides() -> StatusColorOverrides {
        guard let stored: [String: Any] = store.read(key: "app.statusColorOverrides"),
              let data = try? JSONSerialization.data(withJSONObject: stored),
              let overrides = try? JSONDecoder().decode(StatusColorOverrides.self, from: data) else {
            return .none
        }
        return overrides
    }

    func setStatusColorOverrides(_ overrides: StatusColorOverrides) {
        if overrides.isEmpty {
            store.write(value: nil, key: "app.statusColorOverrides")
            return
        }
        guard let data = try? JSONEncoder().encode(overrides),
              let value = try? JSONSerialization.jsonObject(with: data) else { return }
        store.write(value: value, key: "app.statusColorOverrides")
    }

    func nativeMenuBarIconsEnabled() -> Bool {
        store.read(key: "app.nativeMenuBarIconsEnabled") ?? false
    }

    func setNativeMenuBarIconsEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.nativeMenuBarIconsEnabled")
    }

    func highContrastEnabled() -> Bool {
        store.read(key: "app.highContrastEnabled") ?? false
    }

    func setHighContrastEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.highContrastEnabled")
    }

    func receiveBetaUpdates() -> Bool {
        store.read(key: "app.receiveBetaUpdates") ?? false
    }

    func setReceiveBetaUpdates(_ receive: Bool) {
        store.write(value: receive, key: "app.receiveBetaUpdates")
    }
}

// MARK: - DeepSeekSettingsRepository

extension AppSettingsFile: DeepSeekSettingsRepository {
    func deepseekAuthEnvVar() -> String {
        store.read(key: "deepseek.authEnvVar") ?? ""
    }

    func setDeepSeekAuthEnvVar(_ envVar: String) {
        store.write(value: envVar, key: "deepseek.authEnvVar")
    }

    // The configuration card and definition-driven lookup use the same vault.
    private var deepseekVault: any SecretVault { vault }

    func saveDeepSeekApiKey(_ key: String) {
        deepseekVault.save(key, "apiKey", provider: "deepseek")
    }

    func getDeepSeekApiKey() -> String? {
        deepseekVault.secret("apiKey", provider: "deepseek")
    }

    func deleteDeepSeekApiKey() {
        _ = deepseekVault.delete("apiKey", provider: "deepseek")
    }

    func hasDeepSeekApiKey() -> Bool {
        getDeepSeekApiKey() != nil
    }
}

