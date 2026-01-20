import Foundation

/// Observable settings manager for ClaudeBar preferences.
/// Note: Provider-specific settings (e.g., Copilot credentials) are managed by the providers themselves.
@MainActor
@Observable
public final class AppSettings {
    public static let shared = AppSettings()

    // MARK: - Theme Settings

    /// The current theme mode (light, dark, system, christmas)
    public var themeMode: String {
        didSet {
            UserDefaults.standard.set(themeMode, forKey: Keys.themeMode)
            // Mark that user has explicitly chosen a theme
            if !isInitializing {
                userHasChosenTheme = true
            }
        }
    }
    
    // MARK: - Update Settings

    /// Whether to receive beta updates (default: false)
    public var receiveBetaUpdates: Bool {
        didSet {
            UserDefaults.standard.set(receiveBetaUpdates, forKey: Keys.receiveBetaUpdates)
            NotificationCenter.default.post(name: .betaUpdatesSettingChanged, object: nil)
        }
    }

    /// Whether the user has explicitly chosen a theme (vs auto-enabled Christmas)
    public var userHasChosenTheme: Bool {
        didSet {
            UserDefaults.standard.set(userHasChosenTheme, forKey: Keys.userHasChosenTheme)
        }
    }

    /// Track initialization to avoid marking theme as user-chosen during init
    private var isInitializing = true

    // MARK: - Claude API Budget Settings

    /// Whether Claude API budget tracking is enabled
    public var claudeApiBudgetEnabled: Bool {
        didSet {
            UserDefaults.standard.set(claudeApiBudgetEnabled, forKey: Keys.claudeApiBudgetEnabled)
        }
    }

    /// The budget threshold for Claude API usage (in dollars)
    public var claudeApiBudget: Decimal {
        didSet {
            UserDefaults.standard.set(NSDecimalNumber(decimal: claudeApiBudget).doubleValue, forKey: Keys.claudeApiBudget)
        }
    }

    // MARK: - Background Sync Settings

    /// Whether background sync is enabled (default: true)
    public var backgroundSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(backgroundSyncEnabled, forKey: Keys.backgroundSyncEnabled)
        }
    }

    /// Background sync interval in seconds (default: 60)
    public var backgroundSyncInterval: TimeInterval {
        didSet {
            UserDefaults.standard.set(backgroundSyncInterval, forKey: Keys.backgroundSyncInterval)
        }
    }



    // MARK: - Initialization

    private init() {
        self.userHasChosenTheme = UserDefaults.standard.bool(forKey: Keys.userHasChosenTheme)
        self.themeMode = UserDefaults.standard.string(forKey: Keys.themeMode) ?? "system"
        self.claudeApiBudgetEnabled = UserDefaults.standard.bool(forKey: Keys.claudeApiBudgetEnabled)
        self.claudeApiBudget = Decimal(UserDefaults.standard.double(forKey: Keys.claudeApiBudget))
        self.receiveBetaUpdates = UserDefaults.standard.bool(forKey: Keys.receiveBetaUpdates)

        // Background sync defaults to DISABLED
        self.backgroundSyncEnabled = UserDefaults.standard.object(forKey: Keys.backgroundSyncEnabled) as? Bool ?? false
        self.backgroundSyncInterval = UserDefaults.standard.object(forKey: Keys.backgroundSyncInterval) as? TimeInterval ?? 60

        // Auto-enable Christmas theme during Dec 24-26 if user hasn't explicitly chosen
        applySeasonalTheme()

        self.isInitializing = false
    }

    // MARK: - Seasonal Theme

    /// Check if today is within the Christmas period (Dec 24-26)
    public static func isChristmasPeriod(date: Date = Date()) -> Bool {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.month, .day], from: date)
        guard let month = components.month, let day = components.day else { return false }
        return month == 12 && (24...26).contains(day)
    }

    /// Apply seasonal theme if appropriate
    private func applySeasonalTheme() {
        let isChristmas = Self.isChristmasPeriod()

        if isChristmas {
            // During Christmas: auto-enable if user hasn't explicitly chosen a theme
            if !userHasChosenTheme {
                themeMode = "christmas"
            }
        } else {
            // After Christmas: revert to system if still on Christmas theme and user didn't explicitly choose it
            if themeMode == "christmas" && !userHasChosenTheme {
                themeMode = "system"
             }
         }
     }
 }

// MARK: - UserDefaults Keys

private extension AppSettings {
    enum Keys {
        static let themeMode = "themeMode"
        static let userHasChosenTheme = "userHasChosenTheme"
        static let claudeApiBudgetEnabled = "claudeApiBudgetEnabled"
        static let claudeApiBudget = "claudeApiBudget"
        static let receiveBetaUpdates = "receiveBetaUpdates"
        static let backgroundSyncEnabled = "backgroundSyncEnabled"
        static let backgroundSyncInterval = "backgroundSyncInterval"
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let betaUpdatesSettingChanged = Notification.Name("betaUpdatesSettingChanged")
}
