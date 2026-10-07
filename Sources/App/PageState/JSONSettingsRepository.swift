import Foundation
import Kit

/// The app's own settings — how pages look and behave — in `~/.claudebar/settings.json`,
/// through `JSONSettingsStore`. Provider, Notify!, alert, leaderboard and hook settings are
/// Kotlin's (ClaudeBarKit), in the same file.
public final class JSONSettingsRepository: AppSettingsRepository, @unchecked Sendable {
    /// Shared instance using the default settings file
    public static let shared = JSONSettingsRepository(store: .shared)

    private let store: JSONSettingsStore

    public init(store: JSONSettingsStore) {
        self.store = store
    }

    // MARK: - AppSettingsRepository

    public func themeMode() -> String {
        store.read(key: "app.themeMode") ?? "system"
    }

    public func setThemeMode(_ mode: String) {
        store.write(value: mode, key: "app.themeMode")
    }

    public func themeTextStyle() -> String {
        store.read(key: "app.themeTextStyle") ?? "themed"
    }

    public func setThemeTextStyle(_ style: String) {
        store.write(value: style, key: "app.themeTextStyle")
    }

    public func themeRunnerShown() -> Bool {
        store.read(key: "app.themeRunner") ?? true
    }

    public func setThemeRunnerShown(_ shown: Bool) {
        store.write(value: shown, key: "app.themeRunner")
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

    public func menuBarAccountLabelsEnabled() -> Bool {
        store.read(key: "app.menuBarAccountLabelsEnabled") ?? true
    }

    public func setMenuBarAccountLabelsEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.menuBarAccountLabelsEnabled")
    }

    public func menuBarProviderLogoEnabled() -> Bool {
        store.read(key: "app.menuBarProviderLogoEnabled") ?? false
    }

    public func setMenuBarProviderLogoEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.menuBarProviderLogoEnabled")
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

    public func hideAccountEmail() -> Bool {
        store.read(key: "app.hideAccountEmail") ?? false
    }

    public func setHideAccountEmail(_ hide: Bool) {
        store.write(value: hide, key: "app.hideAccountEmail")
    }

    public func hideLeaderboardCountry() -> Bool {
        store.read(key: "app.hideLeaderboardCountry") ?? false
    }

    public func setHideLeaderboardCountry(_ hide: Bool) {
        store.write(value: hide, key: "app.hideLeaderboardCountry")
    }

    public func hideLeaderboardName() -> Bool {
        store.read(key: "app.hideLeaderboardName") ?? false
    }

    public func setHideLeaderboardName(_ hide: Bool) {
        store.write(value: hide, key: "app.hideLeaderboardName")
    }

    public func popoverTextSize() -> String {
        store.read(key: "app.popoverTextSize") ?? "medium"
    }

    public func setPopoverTextSize(_ size: String) {
        store.write(value: size, key: "app.popoverTextSize")
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

    public func nativeMenuBarIconsEnabled() -> Bool {
        store.read(key: "app.nativeMenuBarIconsEnabled") ?? false
    }

    public func setNativeMenuBarIconsEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.nativeMenuBarIconsEnabled")
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
}
