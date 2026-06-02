import Foundation
import Domain
import Infrastructure
import ServiceManagement

/// Observable settings manager for ClaudeBar preferences.
/// Thin `@Observable` wrapper around `AppSettingsRepository` for SwiftUI reactivity.
/// All persistence is delegated to the repository (`~/.claudebar/settings.json`).
@MainActor
@Observable
public final class AppSettings {
    public static let shared = AppSettings()

    /// The underlying repository (internal - views access settings through AppSettings properties/methods)
    private let repository: JSONSettingsRepository

    // MARK: - Theme Settings

    /// The current theme mode (light, dark, system, christmas)
    public var themeMode: String {
        didSet {
            repository.setThemeMode(themeMode)
            if !isInitializing {
                userHasChosenTheme = true
            }
        }
    }

    /// Whether the user has explicitly chosen a theme (vs auto-enabled Christmas)
    public var userHasChosenTheme: Bool {
        didSet {
            repository.setUserHasChosenTheme(userHasChosenTheme)
        }
    }

    // MARK: - Display Settings

    /// Whether to show quota as remaining, used, or pace-aware.
    public var usageDisplayMode: UsageDisplayMode {
        didSet {
            repository.setUsageDisplayMode(usageDisplayMode.rawValue)
        }
    }

    /// Whether the menu bar label should show a selected quota percentage instead of the icon.
    public var menuBarPercentageEnabled: Bool {
        didSet {
            repository.setMenuBarPercentageEnabled(menuBarPercentageEnabled)
        }
    }

    /// Whether the menu bar label should show the compact reset duration for the
    /// selected quota. Independent of `menuBarPercentageEnabled`; both can be on
    /// simultaneously (in which case they are joined by " · ").
    public var menuBarDurationEnabled: Bool {
        didSet {
            repository.setMenuBarDurationEnabled(menuBarDurationEnabled)
        }
    }

    /// Provider used for the menu bar percentage label.
    public var menuBarPercentageProviderId: String {
        didSet {
            repository.setMenuBarPercentageProviderId(menuBarPercentageProviderId)
        }
    }

    /// Quota key used for the menu bar percentage label.
    public var menuBarPercentageQuotaKey: String {
        didSet {
            repository.setMenuBarPercentageQuotaKey(menuBarPercentageQuotaKey)
        }
    }

    /// Optional secondary quota key shown alongside the primary in the menu bar
    /// (e.g. weekly next to session). Empty string means no secondary window.
    public var menuBarSecondaryQuotaKey: String {
        didSet {
            repository.setMenuBarSecondaryQuotaKey(menuBarSecondaryQuotaKey)
        }
    }

    /// Whether to show daily usage report cards (API Cost, Token Usage, Working Time)
    public var showDailyUsageCards: Bool {
        didSet {
            repository.setShowDailyUsageCards(showDailyUsageCards)
        }
    }

    // MARK: - Overview Mode Settings

    /// Whether to show all enabled providers at once instead of one at a time
    public var overviewModeEnabled: Bool {
        didSet {
            repository.setOverviewModeEnabled(overviewModeEnabled)
        }
    }

    // MARK: - Background Sync Settings

    /// Whether background sync is enabled (default: false)
    public var backgroundSyncEnabled: Bool {
        didSet {
            repository.setBackgroundSyncEnabled(backgroundSyncEnabled)
        }
    }

    /// Background sync interval in seconds (default: 60)
    public var backgroundSyncInterval: TimeInterval {
        didSet {
            repository.setBackgroundSyncInterval(backgroundSyncInterval)
        }
    }

    // MARK: - Claude API Budget Settings

    /// Whether Claude API budget tracking is enabled
    public var claudeApiBudgetEnabled: Bool {
        didSet {
            repository.setClaudeApiBudgetEnabled(claudeApiBudgetEnabled)
        }
    }

    /// The budget threshold for Claude API usage (in dollars)
    public var claudeApiBudget: Decimal {
        didSet {
            repository.setClaudeApiBudget(NSDecimalNumber(decimal: claudeApiBudget).doubleValue)
        }
    }

    // MARK: - Burn Rate Warning Settings

    /// Whether burn rate-based warnings are enabled (default: false, uses absolute thresholds)
    public var burnRateWarningEnabled: Bool {
        didSet {
            repository.setBurnRateWarningEnabled(burnRateWarningEnabled)
        }
    }

    /// The burn rate multiplier threshold above which warnings fire (default: 1.5)
    public var burnRateThreshold: Double {
        didSet {
            repository.setBurnRateThreshold(burnRateThreshold)
        }
    }

    // MARK: - Update Settings

    /// Whether to receive beta updates (default: false)
    public var receiveBetaUpdates: Bool {
        didSet {
            repository.setReceiveBetaUpdates(receiveBetaUpdates)
            NotificationCenter.default.post(name: .betaUpdatesSettingChanged, object: nil)
        }
    }

    // MARK: - Launch at Login Settings

    /// Whether the app should launch at login (backed by SMAppService, not JSON)
    public var launchAtLogin: Bool {
        didSet {
            guard !isInitializing else { return }
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    // MARK: - Internal

    private var isInitializing = true

    // MARK: - Initialization

    private init(repository: JSONSettingsRepository = .shared) {
        self.repository = repository

        // Load all values from repository
        self.themeMode = repository.themeMode()
        self.userHasChosenTheme = repository.userHasChosenTheme()
        self.claudeApiBudgetEnabled = repository.claudeApiBudgetEnabled()
        self.claudeApiBudget = Decimal(repository.claudeApiBudget())
        self.receiveBetaUpdates = repository.receiveBetaUpdates()
        self.burnRateWarningEnabled = repository.burnRateWarningEnabled()
        self.burnRateThreshold = repository.burnRateThreshold()
        self.showDailyUsageCards = repository.showDailyUsageCards()
        self.overviewModeEnabled = repository.overviewModeEnabled()
        self.backgroundSyncEnabled = repository.backgroundSyncEnabled()
        self.backgroundSyncInterval = repository.backgroundSyncInterval()
        self.menuBarPercentageEnabled = repository.menuBarPercentageEnabled()
        self.menuBarDurationEnabled = repository.menuBarDurationEnabled()
        self.menuBarPercentageProviderId = repository.menuBarPercentageProviderId()
        self.menuBarPercentageQuotaKey = repository.menuBarPercentageQuotaKey()
        self.menuBarSecondaryQuotaKey = repository.menuBarSecondaryQuotaKey()

        if let mode = UsageDisplayMode(rawValue: repository.usageDisplayMode()) {
            self.usageDisplayMode = mode
        } else {
            self.usageDisplayMode = .remaining
        }

        // Launch at login - read from SMAppService (system service, not JSON)
        self.launchAtLogin = SMAppService.mainApp.status == .enabled

        applySeasonalTheme()
        self.isInitializing = false
    }

    // MARK: - Seasonal Theme

    public static func isChristmasPeriod(date: Date = Date()) -> Bool {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.month, .day], from: date)
        guard let month = components.month, let day = components.day else { return false }
        return month == 12 && (24...26).contains(day)
    }

    private func applySeasonalTheme() {
        let isChristmas = Self.isChristmasPeriod()

        if isChristmas {
            if !userHasChosenTheme {
                themeMode = "christmas"
            }
        } else {
            if themeMode == "christmas" && !userHasChosenTheme {
                themeMode = "system"
            }
        }
    }

    // MARK: - Provider Settings Access

    /// Access provider-specific settings for reading/writing in Settings UI.
    /// These are non-observable (loaded into @State) - only app-level settings are @Observable.
    public var provider: ProviderSettingsRepository { repository }
    public var claude: ClaudeSettingsRepository { repository }
    public var codex: CodexSettingsRepository { repository }
    public var kimi: KimiSettingsRepository { repository }
    public var copilot: CopilotSettingsRepository { repository }
    public var zai: ZaiSettingsRepository { repository }
    public var bedrock: BedrockSettingsRepository { repository }
    public var minimax: MiniMaxSettingsRepository { repository }
    public var alibaba: AlibabaSettingsRepository { repository }
    public var hook: HookSettingsRepository { repository }

    /// Extension config repository for dynamic extension provider settings.
    public let extensionConfig: any ExtensionConfigRepository = JSONExtensionConfigRepository(
        settingsStore: .shared
    )
}

// MARK: - Notification Names

extension Notification.Name {
    static let betaUpdatesSettingChanged = Notification.Name("betaUpdatesSettingChanged")
}
