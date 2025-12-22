import SwiftUI
import Domain
import Infrastructure

/// Shared app state observable by all views
@Observable
final class AppState {
    /// The registered providers (rich domain models)
    var providers: [any AIProvider] = []

    /// The overall status across all providers
    var overallStatus: QuotaStatus {
        providers
            .compactMap(\.snapshot?.overallStatus)
            .max() ?? .healthy
    }

    /// Whether any provider is currently refreshing
    var isRefreshing: Bool {
        providers.contains { $0.isSyncing }
    }

    /// Last error message, if any
    var lastError: String?
}

@main
struct ClaudeBarApp: App {
    /// The main domain service - monitors all AI providers
    @State private var monitor: QuotaMonitor

    /// Shared app state
    @State private var appState = AppState()

    /// Notification observer
    private let notificationObserver = NotificationQuotaObserver()

    init() {
        // Create providers with their probes (rich domain models)
        let providers: [any AIProvider] = [
            ClaudeProvider(probe: ClaudeUsageProbe()),
            CodexProvider(probe: CodexUsageProbe()),
            GeminiProvider(probe: GeminiUsageProbe()),
        ]

        // Register providers for global access
        AIProviderRegistry.shared.register(providers)

        // Store providers in app state
        let state = AppState()
        state.providers = providers
        appState = state

        // Initialize the domain service with notification observer
        monitor = QuotaMonitor(
            providers: providers,
            statusObserver: notificationObserver
        )

        // Request notification permission
        let observer = notificationObserver
        Task {
            _ = await observer.requestPermission()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(monitor: monitor, appState: appState)
        } label: {
            StatusBarIcon(status: appState.overallStatus)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu bar icon that reflects the overall quota status
struct StatusBarIcon: View {
    let status: QuotaStatus

    var body: some View {
        Image(systemName: iconName)
            .foregroundStyle(status.displayColor)
    }

    private var iconName: String {
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
}
