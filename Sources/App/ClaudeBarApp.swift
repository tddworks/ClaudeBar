@preconcurrency import SwiftUI
import Domain
import Infrastructure
#if ENABLE_SPARKLE
import Sparkle
#endif

/// Shared app state observable by all views
@Observable
@MainActor
final class AppState {
    /// The registered providers (rich domain models)
    var providers: [any AIProvider] = []

    /// The currently selected provider ID (for menu bar icon status)
    var selectedProviderId: String = "claude"

    /// The overall status across all providers
    var overallStatus: QuotaStatus {
        providers
            .compactMap(\.snapshot?.overallStatus)
            .max() ?? .healthy
    }

    /// Status of the currently selected provider (for menu bar icon)
    var selectedProviderStatus: QuotaStatus {
        providers.first { $0.id == selectedProviderId }?.snapshot?.overallStatus ?? .healthy
    }

    /// Whether any provider is currently refreshing
    var isRefreshing: Bool {
        providers.contains { $0.isSyncing }
    }

    /// Last error message, if any
    var lastError: String?

    private var settingsObserver: NSObjectProtocol?

    init(providers: [any AIProvider] = []) {
        self.providers = providers

        // Listen for provider settings changes
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .providerSettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.rebuildProviders()
        }
    }

    
    /// Adds a provider if not already present
    func addProvider(_ provider: any AIProvider) {
        guard !providers.contains(where: { $0.id == provider.id }) else {
            AppLog.providers.debug("Provider already exists: \(provider.id)")
            return
        }
        providers.append(provider)
        AIProviderRegistry.shared.register([provider])
        AppLog.providers.info("Added provider: \(provider.id)")
    }

    /// Removes a provider by ID
    func removeProvider(id: String) {
        providers.removeAll { $0.id == id }
        AppLog.providers.info("Removed provider: \(id)")
    }

    /// Rebuilds providers list based on current settings
    func rebuildProviders() {
        AppLog.providers.info("Rebuilding providers based on settings changes")

        var newProviders: [any AIProvider] = []

        // Add providers based on enable/disable settings
        if AppSettings.shared.claudeEnabled {
            newProviders.append(ClaudeProvider(probe: ClaudeUsageProbe()))
        }
        if AppSettings.shared.codexEnabled {
            newProviders.append(CodexProvider(probe: CodexUsageProbe()))
        }
        if AppSettings.shared.geminiEnabled {
            newProviders.append(GeminiProvider(probe: GeminiUsageProbe()))
        }
        if AppSettings.shared.antigravityEnabled {
            newProviders.append(AntigravityProvider(probe: AntigravityUsageProbe()))
        }
        if AppSettings.shared.zaiEnabled {
            newProviders.append(ZaiProvider(probe: ZaiUsageProbe()))
        }

        // Add Copilot provider if configured
        if AppSettings.shared.copilotEnabled && AppSettings.shared.hasCopilotToken {
            newProviders.append(CopilotProvider(probe: CopilotUsageProbe()))
        }

        // Clear existing providers
        providers.removeAll()

        // Register new providers
        AIProviderRegistry.shared.register(newProviders)

        // Set new providers
        providers = newProviders

        AppLog.providers.info("Rebuilt \(providers.count) providers based on settings")
    }

    /// Rebuilds providers and reinitializes monitor
    func rebuildProvidersAndMonitor() {
        rebuildProviders()
        // Monitor will be reinitialized in the view through the @State variable
    }
}

/// View model to handle provider settings changes
@MainActor
class ProviderSettingsManager: ObservableObject {
    @Published var providers: [any AIProvider] = []
    private let quotaAlerter = QuotaAlerter()
    private var monitor: QuotaMonitor?
    private var settingsObserver: NSObjectProtocol?

    // Public getter for monitor
    var monitorForView: QuotaMonitor? { monitor }

    init(initialProviders: [any AIProvider]) {
        self.providers = initialProviders

        // Initialize monitor
        self.monitor = QuotaMonitor(
            providers: providers,
            statusListener: quotaAlerter
        )

        // Listen for provider settings changes
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .providerSettingsChanged,
            object: nil,
            queue: .main
        ) { _ in
            self.handleProviderSettingsChanged()
        }
    }

    nonisolated deinit {
        if let observer = settingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func handleProviderSettingsChanged() {
        // Rebuild providers based on settings
        var newProviders: [any AIProvider] = []

        if AppSettings.shared.claudeEnabled {
            newProviders.append(ClaudeProvider(probe: ClaudeUsageProbe()))
        }
        if AppSettings.shared.codexEnabled {
            newProviders.append(CodexProvider(probe: CodexUsageProbe()))
        }
        if AppSettings.shared.geminiEnabled {
            newProviders.append(GeminiProvider(probe: GeminiUsageProbe()))
        }
        if AppSettings.shared.antigravityEnabled {
            newProviders.append(AntigravityProvider(probe: AntigravityUsageProbe()))
        }
        if AppSettings.shared.zaiEnabled {
            newProviders.append(ZaiProvider(probe: ZaiUsageProbe()))
        }

        if AppSettings.shared.copilotEnabled && AppSettings.shared.hasCopilotToken {
            newProviders.append(CopilotProvider(probe: CopilotUsageProbe()))
        }

        // Update providers
        providers.removeAll()
        providers = newProviders

        // Reinitialize monitor
        monitor = QuotaMonitor(
            providers: providers,
            statusListener: quotaAlerter
        )
    }
}

@main
struct ClaudeBarApp: App {
    /// The provider settings manager
    @StateObject private var providerManager = ProviderSettingsManager(initialProviders: [])

    /// Alerts users when quota status degrades
    private let quotaAlerter = QuotaAlerter()

    #if ENABLE_SPARKLE
    /// Sparkle updater for auto-updates
    @State private var sparkleUpdater = SparkleUpdater()
    #endif

    init() {
        AppLog.ui.info("ClaudeBar initializing...")

        var providers: [any AIProvider] = []

        // Add providers based on enable/disable settings
        if AppSettings.shared.claudeEnabled {
            providers.append(ClaudeProvider(probe: ClaudeUsageProbe()))
            AppLog.providers.info("Added Claude provider")
        } else {
            AppLog.providers.debug("Claude provider disabled")
        }

        if AppSettings.shared.codexEnabled {
            providers.append(CodexProvider(probe: CodexUsageProbe()))
            AppLog.providers.info("Added Codex provider")
        } else {
            AppLog.providers.debug("Codex provider disabled")
        }

        if AppSettings.shared.geminiEnabled {
            providers.append(GeminiProvider(probe: GeminiUsageProbe()))
            AppLog.providers.info("Added Gemini provider")
        } else {
            AppLog.providers.debug("Gemini provider disabled")
        }

        if AppSettings.shared.antigravityEnabled {
            providers.append(AntigravityProvider(probe: AntigravityUsageProbe()))
            AppLog.providers.info("Added Antigravity provider")
        } else {
            AppLog.providers.debug("Antigravity provider disabled")
        }

        if AppSettings.shared.zaiEnabled {
            providers.append(ZaiProvider(probe: ZaiUsageProbe()))
            AppLog.providers.info("Added Z.ai provider")
        } else {
            AppLog.providers.debug("Z.ai provider disabled")
        }

        AppLog.providers.info("Created \(providers.count) providers based on settings")

        // Add Copilot provider if configured
        if AppSettings.shared.copilotEnabled && AppSettings.shared.hasCopilotToken {
            providers.append(CopilotProvider(probe: CopilotUsageProbe()))
            AppLog.providers.info("Added Copilot provider (enabled and configured)")
        } else if AppSettings.shared.copilotEnabled {
            AppLog.providers.debug("Copilot enabled but no token configured")
        }

        // Register providers for global access
        AIProviderRegistry.shared.register(providers)
        AppLog.providers.info("Registered \(providers.count) providers")

        // Initialize provider manager with providers
        _providerManager = StateObject(wrappedValue: ProviderSettingsManager(initialProviders: providers))

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
            MenuContentView(monitor: providerManager.monitorForView!, appState: AppState(providers: providerManager.providers), quotaAlerter: quotaAlerter)
                .themeProvider(currentThemeMode)
                .environment(\.sparkleUpdater, sparkleUpdater)
            #else
            MenuContentView(monitor: providerManager.monitorForView!, appState: AppState(providers: providerManager.providers), quotaAlerter: quotaAlerter)
                .themeProvider(currentThemeMode)
            #endif
        } label: {
            let appState = AppState(providers: providerManager.providers)
            StatusBarIcon(status: appState.selectedProviderStatus, isChristmas: currentThemeMode == .christmas)
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
