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

        let newProviders = AppSettings.buildEnabledProviders()

        // Clear existing providers
        providers.removeAll()

        // Register new providers
        AIProviderRegistry.shared.register(newProviders)

        // Set new providers
        providers = newProviders

        AppLog.providers.info("Rebuilt \(providers.count) providers based on settings")
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
        let newProviders = AppSettings.buildEnabledProviders()

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

        let providers = AppSettings.buildEnabledProviders()

        // Register providers for global access
        AIProviderRegistry.shared.register(providers)
        AppLog.providers.info("Registered \(providers.count) providers: \(providers.map(\.id).joined(separator: ", "))")

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
