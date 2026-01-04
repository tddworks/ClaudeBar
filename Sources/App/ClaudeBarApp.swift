import SwiftUI
import Domain
import Infrastructure
#if ENABLE_SPARKLE
import Sparkle
#endif

@main
struct ClaudeBarApp: App {
    /// The main domain service - monitors all AI providers
    /// This is the single source of truth for providers and their state
    @State private var monitor: QuotaMonitor

    /// Alerts users when quota status degrades
    private let quotaAlerter = NotificationAlerter()

    #if ENABLE_SPARKLE
    /// Sparkle updater for auto-updates
    @State private var sparkleUpdater = SparkleUpdater()
    #endif

    init() {
        AppLog.ui.info("ClaudeBar initializing...")

        // Create the shared repositories
        let settingsRepository = UserDefaultsProviderSettingsRepository.shared
        let credentialRepository = UserDefaultsCredentialRepository.shared
        let configRepository = UserDefaultsProviderConfigRepository.shared

        // Create all providers with their probes (rich domain models)
        // Each provider manages its own isEnabled state (persisted via ProviderSettingsRepository)
        // Each probe checks isAvailable() for credentials/prerequisites
        let repository = AIProviders(providers: [
            ClaudeProvider(probe: ClaudeUsageProbe(), passProbe: ClaudePassProbe(), settingsRepository: settingsRepository),
            CodexProvider(probe: CodexUsageProbe(), settingsRepository: settingsRepository),
            GeminiProvider(probe: GeminiUsageProbe(), settingsRepository: settingsRepository),
            AntigravityProvider(probe: AntigravityUsageProbe(), settingsRepository: settingsRepository),
            ZaiProvider(probe: ZaiUsageProbe(), settingsRepository: settingsRepository),
            CopilotProvider(probe: CopilotUsageProbe(), settingsRepository: settingsRepository, credentialRepository: credentialRepository, configRepository: configRepository),
        ])
        AppLog.providers.info("Created \(repository.all.count) providers")

        // Initialize the domain service with quota alerter
        // QuotaMonitor automatically validates selected provider on init
        monitor = QuotaMonitor(
            providers: repository,
            alerter: quotaAlerter
        )
        AppLog.monitor.info("QuotaMonitor initialized")

        // Note: Notification permission is requested in onAppear, not here
        // Menu bar apps need the run loop to be active before requesting permissions

        AppLog.ui.info("ClaudeBar initialization complete")
    }

    /// App settings for theme
    @State private var settings = AppSettings.shared

    /// Current theme mode from settings
    private var currentThemeMode: ThemeMode {
        ThemeMode(rawValue: settings.themeMode) ?? .system
    }

    var body: some Scene {
        MenuBarExtra {
            #if ENABLE_SPARKLE
            MenuContentView(monitor: monitor, quotaAlerter: quotaAlerter)
                .themeProvider(currentThemeMode)
                .environment(\.sparkleUpdater, sparkleUpdater)
            #else
            MenuContentView(monitor: monitor, quotaAlerter: quotaAlerter)
                .themeProvider(currentThemeMode)
            #endif
        } label: {
            // Show overall status (worst across all enabled providers) in menu bar
            StatusBarIcon(status: monitor.overallStatus, isChristmas: currentThemeMode == .christmas)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu bar icon that reflects the overall quota status
struct StatusBarIcon: View {
    let status: QuotaStatus
    var isChristmas: Bool = false

    var body: some View {
        Image(systemName: iconName)
            .symbolRenderingMode(.palette)
            .foregroundStyle(iconColor)
    }

    private var iconName: String {
        if isChristmas {
            return "snowflake"
        }
        switch status {
        case .depleted:
            return "chart.bar.xaxis"
        case .critical:
            return "exclamationmark.triangle.fill"
        case .warning:
            return "chart.bar.fill"
        case .healthy:
            return "chart.bar.fill"
        }
    }

    private var iconColor: Color {
        if isChristmas {
            return AppTheme.christmasGold
        }
        return status.displayColor
    }
}

// MARK: - StatusBarIcon Preview

#Preview("StatusBarIcon - All States") {
    HStack(spacing: 30) {
        VStack {
            StatusBarIcon(status: .healthy)
            Text("HEALTHY")
                .font(.caption)
                .foregroundStyle(.green)
        }
        VStack {
            StatusBarIcon(status: .warning)
            Text("WARNING")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        VStack {
            StatusBarIcon(status: .critical)
            Text("CRITICAL")
                .font(.caption)
                .foregroundStyle(.red)
        }
        VStack {
            StatusBarIcon(status: .depleted)
            Text("DEPLETED")
                .font(.caption)
                .foregroundStyle(.red)
        }
        VStack {
            StatusBarIcon(status: .healthy, isChristmas: true)
            Text("CHRISTMAS")
                .font(.caption)
                .foregroundStyle(AppTheme.christmasGold)
        }
    }
    .padding(40)
    .background(Color.black)
}
