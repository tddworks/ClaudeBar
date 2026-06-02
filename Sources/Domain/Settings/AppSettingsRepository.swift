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

    func menuBarPercentageProviderId() -> String
    func setMenuBarPercentageProviderId(_ providerId: String)

    func menuBarPercentageQuotaKey() -> String
    func setMenuBarPercentageQuotaKey(_ quotaKey: String)

    func menuBarSecondaryQuotaKey() -> String
    func setMenuBarSecondaryQuotaKey(_ quotaKey: String)

    func showDailyUsageCards() -> Bool
    func setShowDailyUsageCards(_ show: Bool)

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

    // MARK: - Updates

    func receiveBetaUpdates() -> Bool
    func setReceiveBetaUpdates(_ receive: Bool)
}
