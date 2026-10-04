import Quotas
import DataSources
import Providers
import Foundation
import Mockable

/// Repository protocol for all app-level settings (display, sync, budget, etc.).
/// Provider-specific settings live in `ProviderSettingsRepository` sub-protocols.
///
/// Both protocols share one backing store (`~/.claudebar/settings.json`).
/// `AppSettings` wraps this as an `@Observable` for SwiftUI.
@Mockable
public protocol AppSettingsRepository: Sendable {
    // MARK: - Theme

    func themeMode() -> String
    func setThemeMode(_ mode: String)

    func userHasChosenTheme() -> Bool
    func setUserHasChosenTheme(_ chosen: Bool)

    // MARK: - Display

    func usageDisplayMode() -> String
    func setUsageDisplayMode(_ mode: String)

    func menuBarPercentageEnabled() -> Bool
    func setMenuBarPercentageEnabled(_ enabled: Bool)

    func menuBarDurationEnabled() -> Bool
    func setMenuBarDurationEnabled(_ enabled: Bool)

    func menuBarAccountLabelsEnabled() -> Bool
    func setMenuBarAccountLabelsEnabled(_ enabled: Bool)

    /// The provider's logo even when it's the only readout (off: only when
    /// readouts need telling apart).
    func menuBarProviderLogoEnabled() -> Bool
    func setMenuBarProviderLogoEnabled(_ enabled: Bool)

    func menuBarStackedEnabled() -> Bool
    func setMenuBarStackedEnabled(_ enabled: Bool)

    func menuBarStackedSize() -> String
    func setMenuBarStackedSize(_ size: String)

    func menuBarPercentageProviderId() -> String
    func setMenuBarPercentageProviderId(_ providerId: String)

    /// Additional providers displayed after the primary, limited to two.
    func menuBarAdditionalProviderIds() -> [String]
    func setMenuBarAdditionalProviderIds(_ providerIds: [String])

    func menuBarProviderSettings() -> [String: MenuBarProviderSettings]
    func setMenuBarProviderSettings(_ settings: [String: MenuBarProviderSettings])

    func menuBarPercentageQuotaKey() -> String
    func setMenuBarPercentageQuotaKey(_ quotaKey: String)

    func menuBarSecondaryQuotaKey() -> String
    func setMenuBarSecondaryQuotaKey(_ quotaKey: String)

    func showDailyUsageCards() -> Bool
    func setShowDailyUsageCards(_ show: Bool)

    /// *Hide account email* (#375): emails show masked in the popover and menu bar.
    func hideAccountEmail() -> Bool
    func setHideAccountEmail(_ hide: Bool)

    /// Your country on the Leaderboard globe shows as `🌍 ••` in the popover.
    func hideLeaderboardCountry() -> Bool
    func setHideLeaderboardCountry(_ hide: Bool)

    /// Your Leaderboard username shows as `@i•••` in the popover.
    func hideLeaderboardName() -> Bool
    func setHideLeaderboardName(_ hide: Bool)

    // MARK: - Notch

    /// Whether the notch live activity is shown (default: false).
    func notchEnabled() -> Bool
    func setNotchEnabled(_ enabled: Bool)

    // MARK: - Touch Bar

    /// Whether Touch Bar status integration is enabled (default: true).
    func touchBarEnabled() -> Bool
    func setTouchBarEnabled(_ enabled: Bool)

    // MARK: - Overview

    func overviewModeEnabled() -> Bool
    func setOverviewModeEnabled(_ enabled: Bool)

    // MARK: - Background Sync

    func backgroundSyncEnabled() -> Bool
    func setBackgroundSyncEnabled(_ enabled: Bool)

    func backgroundSyncInterval() -> TimeInterval
    func setBackgroundSyncInterval(_ interval: TimeInterval)

    // MARK: - Claude API Budget

    func claudeApiBudgetEnabled() -> Bool
    func setClaudeApiBudgetEnabled(_ enabled: Bool)

    func claudeApiBudget() -> Double
    func setClaudeApiBudget(_ amount: Double)

    // MARK: - Burn Rate Warning

    func burnRateWarningEnabled() -> Bool
    func setBurnRateWarningEnabled(_ enabled: Bool)

    func burnRateThreshold() -> Double
    func setBurnRateThreshold(_ threshold: Double)

    /// Monochrome provider marks in the menu bar; opt-in, across all accounts.
    func nativeMenuBarIconsEnabled() -> Bool
    func setNativeMenuBarIconsEnabled(_ enabled: Bool)

    // MARK: - Status Colors

    /// The user's own status colors, overriding the theme per status.
    func statusColorOverrides() -> StatusColorOverrides
    func setStatusColorOverrides(_ overrides: StatusColorOverrides)

    /// Whether the built-in appearance-aware High Contrast palette is on.
    func highContrastEnabled() -> Bool
    func setHighContrastEnabled(_ enabled: Bool)

    // MARK: - Updates

    func receiveBetaUpdates() -> Bool
    func setReceiveBetaUpdates(_ receive: Bool)
}
