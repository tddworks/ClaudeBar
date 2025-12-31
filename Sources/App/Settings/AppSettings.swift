import Foundation
import Infrastructure
import Domain

/// Observable settings manager for ClaudeBar preferences.
/// Credentials are stored in UserDefaults via CredentialStore.
@MainActor
@Observable
public final class AppSettings {
    public static let shared = AppSettings()

    private let credentialStore: any CredentialStore

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

    /// Whether the user has explicitly chosen a theme (vs auto-enabled Christmas)
    public var userHasChosenTheme: Bool {
        didSet {
            UserDefaults.standard.set(userHasChosenTheme, forKey: Keys.userHasChosenTheme)
        }
    }

    /// Track initialization to avoid marking theme as user-chosen during init
    private var isInitializing = true

    // MARK: - Provider Settings

    /// Whether Claude provider is enabled
    public var claudeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(claudeEnabled, forKey: Keys.claudeEnabled)
            NotificationCenter.default.post(name: .providerSettingsChanged, object: nil)
        }
    }

    /// Whether Codex provider is enabled
    public var codexEnabled: Bool {
        didSet {
            UserDefaults.standard.set(codexEnabled, forKey: Keys.codexEnabled)
            NotificationCenter.default.post(name: .providerSettingsChanged, object: nil)
        }
    }

    /// Whether Gemini provider is enabled
    public var geminiEnabled: Bool {
        didSet {
            UserDefaults.standard.set(geminiEnabled, forKey: Keys.geminiEnabled)
            NotificationCenter.default.post(name: .providerSettingsChanged, object: nil)
        }
    }

    /// Whether Antigravity provider is enabled
    public var antigravityEnabled: Bool {
        didSet {
            UserDefaults.standard.set(antigravityEnabled, forKey: Keys.antigravityEnabled)
            NotificationCenter.default.post(name: .providerSettingsChanged, object: nil)
        }
    }

    /// Whether Z.ai provider is enabled
    public var zaiEnabled: Bool {
        didSet {
            UserDefaults.standard.set(zaiEnabled, forKey: Keys.zaiEnabled)
            NotificationCenter.default.post(name: .providerSettingsChanged, object: nil)
        }
    }

    /// Whether GitHub Copilot provider is enabled
    public var copilotEnabled: Bool {
        didSet {
            UserDefaults.standard.set(copilotEnabled, forKey: Keys.copilotEnabled)
        }
    }

    /// The GitHub username for Copilot API calls
    public var githubUsername: String {
        didSet {
            credentialStore.save(githubUsername, forKey: CredentialKey.githubUsername)
        }
    }

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

    // MARK: - Update Settings

    /// Whether to receive beta updates (default: false)
    public var receiveBetaUpdates: Bool {
        didSet {
            UserDefaults.standard.set(receiveBetaUpdates, forKey: Keys.receiveBetaUpdates)
            NotificationCenter.default.post(name: .betaUpdatesSettingChanged, object: nil)
        }
    }

    // MARK: - Token Management

    /// Whether a GitHub Copilot token is configured
    public var hasCopilotToken: Bool {
        credentialStore.exists(forKey: CredentialKey.githubToken)
    }

    /// Saves the GitHub Copilot token
    public func saveCopilotToken(_ token: String) {
        credentialStore.save(token, forKey: CredentialKey.githubToken)
        AppLog.credentials.info("Saved GitHub Copilot token")
    }

    /// Retrieves the GitHub Copilot token
    public func getCopilotToken() -> String? {
        let token = credentialStore.get(forKey: CredentialKey.githubToken)
        AppLog.credentials.debug("Retrieved GitHub Copilot token: \(token != nil ? "exists" : "nil")")
        return token
    }

    /// Deletes the GitHub Copilot token
    public func deleteCopilotToken() {
        credentialStore.delete(forKey: CredentialKey.githubToken)
        AppLog.credentials.info("Deleted GitHub Copilot token")
    }

    // MARK: - Initialization

    private init(credentialStore: any CredentialStore = UserDefaultsCredentialStore.shared) {
        self.credentialStore = credentialStore
        self.userHasChosenTheme = UserDefaults.standard.bool(forKey: Keys.userHasChosenTheme)
        self.themeMode = UserDefaults.standard.string(forKey: Keys.themeMode) ?? "system"

        // Initialize provider enable/disable settings with defaults
        self.claudeEnabled = UserDefaults.standard.bool(forKey: Keys.claudeEnabled) || true
        self.codexEnabled = UserDefaults.standard.bool(forKey: Keys.codexEnabled) || true
        self.geminiEnabled = UserDefaults.standard.bool(forKey: Keys.geminiEnabled) || true
        self.antigravityEnabled = UserDefaults.standard.bool(forKey: Keys.antigravityEnabled) || true
        self.zaiEnabled = UserDefaults.standard.bool(forKey: Keys.zaiEnabled) || true

        self.copilotEnabled = UserDefaults.standard.bool(forKey: Keys.copilotEnabled)
        self.githubUsername = credentialStore.get(forKey: CredentialKey.githubUsername) ?? ""
        self.claudeApiBudgetEnabled = UserDefaults.standard.bool(forKey: Keys.claudeApiBudgetEnabled)
        self.claudeApiBudget = Decimal(UserDefaults.standard.double(forKey: Keys.claudeApiBudget))
        self.receiveBetaUpdates = UserDefaults.standard.bool(forKey: Keys.receiveBetaUpdates)

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
        static let claudeEnabled = "claudeEnabled"
        static let codexEnabled = "codexEnabled"
        static let geminiEnabled = "geminiEnabled"
        static let antigravityEnabled = "antigravityEnabled"
        static let zaiEnabled = "zaiEnabled"
        static let copilotEnabled = "copilotEnabled"
        static let claudeApiBudgetEnabled = "claudeApiBudgetEnabled"
        static let claudeApiBudget = "claudeApiBudget"
        static let receiveBetaUpdates = "receiveBetaUpdates"
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let betaUpdatesSettingChanged = Notification.Name("betaUpdatesSettingChanged")
    static let providerSettingsChanged = Notification.Name("providerSettingsChanged")
}
