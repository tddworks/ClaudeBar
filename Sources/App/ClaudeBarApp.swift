import SwiftUI
import Domain
import Infrastructure
#if ENABLE_SPARKLE
import Sparkle
#endif

extension Notification.Name {
    static let hookSettingsChanged = Notification.Name("com.tddworks.claudebar.hookSettingsChanged")
}

@main
struct ClaudeBarApp: App {
    /// The main domain service - monitors all AI providers
    /// This is the single source of truth for providers and their state
    @State private var monitor: QuotaMonitor

    /// Monitors Claude Code sessions via hook events
    @State private var sessionMonitor = SessionMonitor()

    /// The hook HTTP server that receives events from Claude Code
    private let hookServer = HookHTTPServer()

    /// Task for the hook server event loop (allows cancellation on toggle off)
    @State private var hookServerTask: Task<Void, Never>?

    /// Alerts users when quota status degrades
    private let quotaAlerter = NotificationAlerter()

    /// Sends session start/end notifications
    private let sessionAlertSender = SystemAlertSender()

    #if ENABLE_SPARKLE
    /// Sparkle updater for auto-updates
    @State private var sparkleUpdater = SparkleUpdater()
    #endif

    init() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        AppLog.ui.info("ClaudeBar v\(version) (\(build)) initializing...")

        // Create the shared settings repository (JSON-backed: ~/.claudebar/settings.json)
        // JSONSettingsRepository implements all sub-protocols:
        // - AppSettingsRepository (app-level display/sync settings)
        // - ProviderSettingsRepository + all provider sub-protocols
        // - HookSettingsRepository
        let settingsRepository = JSONSettingsRepository.shared

        // Create all providers with their probes (rich domain models)
        // Each provider manages its own isEnabled state (persisted via ProviderSettingsRepository)
        // Each probe checks isAvailable() for credentials/prerequisites
        let repository = AIProviders(providers: [
            ClaudeProvider(
                cliProbe: ClaudeUsageProbe(),
                apiProbe: ClaudeAPIUsageProbe(),
                passProbe: ClaudePassProbe(),
                settingsRepository: settingsRepository,
                dailyUsageAnalyzer: ClaudeDailyUsageAnalyzer()
            ),
            CodexProvider(
                rpcProbe: CodexUsageProbe(),
                apiProbe: CodexAPIUsageProbe(),
                settingsRepository: settingsRepository
            ),
            GeminiProvider(probe: GeminiUsageProbe(), settingsRepository: settingsRepository),
            AntigravityProvider(probe: AntigravityUsageProbe(), settingsRepository: settingsRepository),
            ZaiProvider(
                probe: ZaiUsageProbe(settingsRepository: settingsRepository),
                settingsRepository: settingsRepository
            ),
            CopilotProvider(
                billingProbe: CopilotUsageProbe(settingsRepository: settingsRepository),
                internalProbe: CopilotInternalAPIProbe(settingsRepository: settingsRepository),
                settingsRepository: settingsRepository
            ),
            BedrockProvider(
                probe: BedrockUsageProbe(settingsRepository: settingsRepository),
                settingsRepository: settingsRepository
            ),
            AmpCodeProvider(probe: AmpCodeUsageProbe(), settingsRepository: settingsRepository),
            KimiProvider(
                cliProbe: KimiCLIUsageProbe(),
                apiProbe: KimiUsageProbe(),
                settingsRepository: settingsRepository
            ),
            KiroProvider(probe: KiroUsageProbe(), settingsRepository: settingsRepository),
            CursorProvider(probe: CursorUsageProbe(), settingsRepository: settingsRepository),
            MiniMaxProvider(
                probe: MiniMaxUsageProbe(settingsRepository: settingsRepository),
                settingsRepository: settingsRepository
            ),
            AlibabaProvider(
                probe: AlibabaUsageProbe(settingsRepository: settingsRepository, cookieProvider: AlibabaBrowserCookieProvider()),
                settingsRepository: settingsRepository
            ),
            MistralProvider(
                probe: MistralUsageProbe(),
                settingsRepository: settingsRepository
            ),
        ])
        AppLog.providers.info("Created \(repository.all.count) providers")

        // Initialize the domain service with quota alerter
        // QuotaMonitor automatically validates selected provider on init
        monitor = QuotaMonitor(
            providers: repository,
            alerter: quotaAlerter
        )
        AppLog.monitor.info("QuotaMonitor initialized")

        // Load user extensions from ~/.claudebar/extensions/
        let extensionRegistry = ExtensionRegistry(
            settingsRepository: settingsRepository,
            configRepository: AppSettings.shared.extensionConfig
        )
        let extensionProviders = extensionRegistry.loadExtensions(into: monitor)
        if !extensionProviders.isEmpty {
            AppLog.providers.info("Loaded \(extensionProviders.count) extension provider(s): \(extensionProviders.map(\.name).joined(separator: ", "))")
        }

        // Start hook server if hooks are enabled
        if settingsRepository.isHookEnabled() {
            startHookServer()
        }

        // Note: Notification permission is requested in onAppear, not here
        // Menu bar apps need the run loop to be active before requesting permissions

        AppLog.ui.info("ClaudeBar initialization complete")
    }

    /// App settings for theme
    @State private var settings = AppSettings.shared

    /// Status of selected provider, considering burn rate setting
    private var effectiveSelectedProviderStatus: QuotaStatus {
        guard let snapshot = monitor.selectedProvider?.snapshot else { return .healthy }
        if settings.burnRateWarningEnabled {
            return snapshot.paceAwareOverallStatus(burnRateThreshold: settings.burnRateThreshold)
        }
        return snapshot.overallStatus
    }

    private var menuBarPercentageDisplay: MenuBarPercentageDisplay? {
        guard settings.menuBarPercentageEnabled else { return nil }

        return monitor.menuBarPercentageDisplay(
            providerId: settings.menuBarPercentageProviderId,
            quotaKey: settings.menuBarPercentageQuotaKey,
            mode: settings.usageDisplayMode,
            burnRateWarningEnabled: settings.burnRateWarningEnabled,
            burnRateThreshold: settings.burnRateThreshold
        )
    }

    /// Current theme mode from settings
    private var currentThemeMode: ThemeMode {
        ThemeMode(rawValue: settings.themeMode) ?? .system
    }

    private func startHookServer() {
        // Cancel any existing server task
        hookServerTask?.cancel()
        hookServer.stop()

        hookServerTask = Task {
            do {
                let events = try await hookServer.start()
                AppLog.hooks.info("Hook server started, listening for events")
                for await event in events {
                    await sessionMonitor.processEvent(event)
                    await sendSessionNotification(for: event)
                }
            } catch {
                AppLog.hooks.error("Failed to start hook server: \(error.localizedDescription)")
            }
        }
    }

    func stopHookServer() {
        hookServerTask?.cancel()
        hookServerTask = nil
        hookServer.stop()
    }

    @MainActor private func sendSessionNotification(for event: SessionEvent) {
        let projectName = (event.cwd as NSString).lastPathComponent

        switch event.eventName {
        case .sessionStart:
            Task {
                try? await sessionAlertSender.send(
                    title: "Claude Code Started",
                    body: "Session started in \(projectName)",
                    categoryIdentifier: "SESSION_START"
                )
            }
        case .sessionEnd:
            let taskCount = sessionMonitor.recentSessions.first?.completedTaskCount ?? 0
            let duration = sessionMonitor.recentSessions.first?.durationDescription ?? ""
            let summary = taskCount > 0
                ? "Completed \(taskCount) task\(taskCount == 1 ? "" : "s") in \(duration)"
                : "Session ended after \(duration)"
            Task {
                try? await sessionAlertSender.send(
                    title: "Claude Code Finished",
                    body: "\(projectName) — \(summary)",
                    categoryIdentifier: "SESSION_END"
                )
            }
        default:
            break
        }
    }

    var body: some Scene {
        MenuBarExtra {
            #if ENABLE_SPARKLE
            MenuContentView(monitor: monitor, sessionMonitor: sessionMonitor, quotaAlerter: quotaAlerter) { enabled in
                    if enabled { startHookServer() } else { stopHookServer() }
                }
                .appThemeProvider(themeModeId: settings.themeMode)
                .environment(\.sparkleUpdater, sparkleUpdater)
            #else
            MenuContentView(monitor: monitor, sessionMonitor: sessionMonitor, quotaAlerter: quotaAlerter) { enabled in
                    if enabled { startHookServer() } else { stopHookServer() }
                }
                .appThemeProvider(themeModeId: settings.themeMode)
            #endif
        } label: {
            // Show overall status + active session indicator in menu bar
            if let display = menuBarPercentageDisplay {
                StatusBarPercentageLabel(display: display, activeSession: sessionMonitor.activeSession)
                    .appThemeProvider(themeModeId: settings.themeMode)
            } else {
                StatusBarIcon(status: effectiveSelectedProviderStatus, activeSession: sessionMonitor.activeSession)
                    .appThemeProvider(themeModeId: settings.themeMode)
            }
        }
        .menuBarExtraStyle(.window)
    }

}

private func sessionPhaseColor(_ phase: ClaudeSession.Phase) -> Color {
    phase.color
}

/// The menu bar icon that reflects the overall quota status.
/// When a Claude Code session is active, shows a terminal icon with phase color.
/// Uses theme's `statusBarIconName` if set, otherwise shows status-based icons.
struct StatusBarIcon: View {
    let status: QuotaStatus
    var activeSession: ClaudeSession? = nil

    @Environment(\.appTheme) private var theme

    var body: some View {
        if let session = activeSession {
            // Active session: show terminal icon with phase color
            HStack(spacing: 3) {
                Image(systemName: "terminal.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(sessionPhaseColor(session.phase))
                Image(systemName: iconName)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(iconColor)
            }
        } else {
            Image(systemName: iconName)
                .symbolRenderingMode(.palette)
                .foregroundStyle(iconColor)
        }
    }

    private var iconName: String {
        // Use theme's custom icon if provided
        if let themeIcon = theme.statusBarIconName {
            return themeIcon
        }
        // Otherwise use status-based icon
        switch status {
        case .depleted:
            return "chart.bar.xaxis"
        case .critical:
            return "exclamationmark.triangle.fill"
        case .warning, .healthy:
            return "chart.bar.fill"
        }
    }

    private var iconColor: Color {
        theme.statusColor(for: status)
    }
}

/// The menu bar percentage label for an opt-in provider/quota selection.
struct StatusBarPercentageLabel: View {
    let display: MenuBarPercentageDisplay
    var activeSession: ClaudeSession? = nil

    @Environment(\.appTheme) private var theme

    var body: some View {
        let statusColor = theme.statusColor(for: display.status)

        HStack(spacing: 3) {
            if let session = activeSession {
                Image(systemName: "terminal.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(sessionPhaseColor(session.phase))
            }

            Image(nsImage: StatusBarPercentageImageRenderer.image(
                text: display.text,
                color: statusColor
            ))
            .renderingMode(.original)
            .accessibilityLabel(display.text)
        }
    }

}

/// Renders status text as an original-color image because macOS can ignore
/// `Text.foregroundStyle` inside a `MenuBarExtra` label.
private enum StatusBarPercentageImageRenderer {
    @MainActor
    static func image(text: String, color: Color) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(color),
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedText.size()
        let imageSize = NSSize(width: ceil(textSize.width), height: ceil(textSize.height))
        let image = NSImage(size: imageSize, flipped: false) { _ in
            attributedText.draw(at: .zero)
            return true
        }
        image.isTemplate = false

        return image
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
            StatusBarIcon(status: .healthy)
                .appThemeProvider(themeModeId: "cli")
            Text("CLI")
                .font(.caption)
                .foregroundStyle(CLITheme().accentPrimary)
        }
        VStack {
            StatusBarIcon(status: .healthy)
                .appThemeProvider(themeModeId: "christmas")
            Text("CHRISTMAS")
                .font(.caption)
                .foregroundStyle(ChristmasTheme().accentPrimary)
        }
    }
    .padding(40)
    .background(Color.black)
}
