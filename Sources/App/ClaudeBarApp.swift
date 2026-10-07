import SwiftUI
import Kit
import MenuBarExtraAccess
#if ENABLE_SPARKLE
import Sparkle
#endif

extension Notification.Name {
    static let hookSettingsChanged = Notification.Name("com.tddworks.claudebar.hookSettingsChanged")

}

/// Started by `ClaudeBarMain` — never while it hosts tests (see `LaunchMode`).
struct ClaudeBarApp: App {
    /// The single source of truth for providers and their state — Kotlin's (MODULAR_DESIGN §5).
    private let monitor: QuotaMonitor = Kit.shared.monitor

    /// *New terminal sessions* — which login `claude` / `codex` start with.
    private let newSessions: NewSessions = Kit.shared.newSessions

    /// *Quota alerts* — the person's own percentages (#68).
    private let quotaAlerts: QuotaAlerts = Kit.shared.quotaAlerts

    /// Claude Code's sessions — Kotlin's, read through the kit (MODULAR_DESIGN §5).
    private let sessionMonitor: SessionMonitor = Kit.shared.sessions

    /// Drives the menu-bar pixels and the background-refresh lifecycle
    /// imperatively, outside SwiftUI — the MenuBarExtra label hosting can
    /// permanently stop re-evaluating after system sleep (issue #192).
    private let statusItemDriver: StatusItemLabelDriver

    /// Draws Claude Code session and quota state into the notch. Comes up and
    /// goes down with `app.notchEnabled`; does nothing until it is turned on.
    private let notchDriver: NotchWindowDriver

    /// Exports quota and menu-bar status to ~/.claudebar/status.json for Touch Bar, BTT, and external scripts.
    private let statusExportDriver: StatusExportDriver
    private let leaderboard: Leaderboard

    /// Binding required by `.menuBarExtraAccess`; also enables programmatic
    /// dropdown control if ever needed.
    @State private var isMenuPresented = false

    @Environment(\.openWindow) private var openWindow

    /// Receives `claudebar://` URLs. Lives outside SwiftUI's scene routing,
    /// which cannot reach a MenuBarExtra (see AppDelegate).
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Alerts users when quota status degrades
    private let quotaAlerter: NotificationAlerter = Kit.shared.notifications

    #if ENABLE_SPARKLE
    /// Sparkle updater for auto-updates
    @State private var sparkleUpdater = SparkleUpdater()
    #endif

    init() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        AppLog.ui.info("ClaudeBar v\(version) (\(build)) initializing...")

        // Every provider, login, alert and upload is built once by the kit
        // (ClaudeBarCore.start): no line here names a provider (TARGET_ARCHITECTURE §10).
        let kit = Kit.shared
        KitObservation.shared.follow(kit)
        AppLog.providers.info("Created \(kit.monitor.providers.all.count) providers")

        let monitor = kit.monitor
        let sessionMonitor = kit.sessions

        // The driver owns the menu-bar pixels and the refresh-loop lifecycle
        // (outside SwiftUI — see StatusItemLabelDriver). Pixels start flowing
        // once `.menuBarExtraAccess` hands over the NSStatusItem.
        statusItemDriver = StatusItemLabelDriver(
            monitor: monitor,
            settings: AppSettings.shared,
            sessionMonitor: sessionMonitor
        )
        statusItemDriver.startMonitoringLifecycle()
        statusItemDriver.startAttachLifecycle()

        notchDriver = NotchWindowDriver(
            monitor: monitor,
            sessionMonitor: sessionMonitor,
            settings: AppSettings.shared
        )
        notchDriver.startWhenLaunched()

        statusExportDriver = StatusExportDriver(
            monitor: monitor,
            settings: AppSettings.shared
        )
        statusExportDriver.start()

        NativeTouchBarDriver.shared.configure(monitor: monitor)

        PersistentTouchBarDriver.shared.configure(
            monitor: monitor,
            settings: AppSettings.shared,
            sessionMonitor: sessionMonitor
        )
        PersistentTouchBarDriver.shared.start()

        // Publishes to a linked Notify! device; sends nothing until one is linked and the switch is on.
        kit.notifyPublisher.start()

        // Uploads only once the user joined; until then it reads nothing.
        leaderboard = Leaderboard(kit.leaderboard)
        kit.leaderboard.start()

        // Start hook server if hooks are enabled
        if Kit.shared.hookSettings.isHookEnabled() {
            // Reconcile installed hooks so newly-added events (e.g.
            // UserPromptSubmit, which revives a stopped session) register for
            // existing users without re-toggling the setting. Turning it on is
            // idempotent — it replaces only ClaudeBar's own matcher entries
            // per event and preserves hooks from other tools.
            if Kit.shared.hookInstaller.isInstalled() {
                _ = Kit.shared.hookInstaller.turn(on: true)
            }
            startHookServer()
        }

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

    /// The hook loop is Kotlin's (activity's `SessionTracking`): it listens, tracks sessions,
    /// sweeps dead ones and announces a session starting and ending.
    private func startHookServer() {
        Kit.shared.sessionTracking.start()
    }

    func stopHookServer() {
        Kit.shared.sessionTracking.stop()
    }

    @MainActor
    private func handle(_ action: URLSchemeAction) {
        switch action {
        case .refresh:
            Task {
                try? await monitor.refreshAll()
            }
        case .open:
            isMenuPresented = true
            NSApp.activate(ignoringOtherApps: true)
        case .settings:
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        case let .use(providerId, name):
            switch newSessions.use(providerId: providerId, name: name) {
            case .used:
                break
            case .unknown:
                AppLog.ui.info("claudebar://use names no login that can be used for new sessions")
            case .waitingForSetup:
                // The shell lines aren't there yet: the popover shows the setup.
                monitor.selectedProviderId = providerId
                isMenuPresented = true
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            Group {
                #if ENABLE_SPARKLE
                MenuContentView(monitor: monitor, sessionMonitor: sessionMonitor, quotaAlerter: quotaAlerter, leaderboard: leaderboard, onClose: { isMenuPresented = false }) { enabled in
                        if enabled { startHookServer() } else { stopHookServer() }
                    }
                    .appThemeProvider(themeModeId: settings.themeMode)
                    .environment(\.popoverTextSize, settings.popoverTextSize)
                    .environment(\.sparkleUpdater, sparkleUpdater)
                #else
                MenuContentView(monitor: monitor, sessionMonitor: sessionMonitor, quotaAlerter: quotaAlerter, leaderboard: leaderboard, onClose: { isMenuPresented = false }) { enabled in
                        if enabled { startHookServer() } else { stopHookServer() }
                    }
                    .appThemeProvider(themeModeId: settings.themeMode)
                    .environment(\.popoverTextSize, settings.popoverTextSize)
                #endif
            }
            .environment(newSessions)
            .environment(quotaAlerts)
            // Opening/closing the dropdown flips `isMenuPresented`, which makes
            // SwiftUI re-evaluate the scene and wipe the AppKit-drawn button
            // image. The dropdown's lifecycle maps 1:1 to those flips, so
            // re-assert the menu-bar pixels on both edges.
            .onAppear { statusItemDriver.reassertPresentation() }
            .onDisappear { statusItemDriver.reassertPresentation() }
        } label: {
            // Deliberately static: the menu-bar pixels are drawn by
            // StatusItemLabelDriver into the status item's button image,
            // because this SwiftUI label hosting can permanently stop
            // re-evaluating after system sleep (issue #192). The placeholder
            // only gives the scene a label to anchor the dropdown to.
            Color.clear.frame(width: 1, height: 1)
                // The label is the one view hosted from launch, so this is
                // where the URL handler meets the App's state (`isMenuPresented`,
                // `openWindow`). The popover content would only be live while
                // the dropdown is open. The handler keeps working even if this
                // hosting later goes dead (issue #192): it captures the state
                // wrappers, not the view.
                .onAppear { appDelegate.onAction = handle }
        }
        // Must be the first scene modifier (extends MenuBarExtra, not Scene).
        .menuBarExtraAccess(isPresented: $isMenuPresented) { statusItem in
            statusItemDriver.attach(statusItem)
        }
        .menuBarExtraStyle(.window)

        // Standalone Settings window (opened from the popover's gear button).
        // Hidden title bar: the sidebar runs the full window height and the
        // traffic lights overlay its top — see SettingsWindowView.
        Window("ClaudeBar Settings", id: "settings") {
            Group {
                #if ENABLE_SPARKLE
                SettingsWindowView(monitor: monitor, leaderboard: leaderboard) { enabled in
                    if enabled { startHookServer() } else { stopHookServer() }
                }
                .appThemeProvider(themeModeId: settings.themeMode)
                .environment(\.sparkleUpdater, sparkleUpdater)
                #else
                SettingsWindowView(monitor: monitor, leaderboard: leaderboard) { enabled in
                    if enabled { startHookServer() } else { stopHookServer() }
                }
                .appThemeProvider(themeModeId: settings.themeMode)
                #endif
            }
            .environment(newSessions)
            .environment(quotaAlerts)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 980, height: 660)
        .windowResizability(.contentMinSize)
        // Without this, the Settings window is the only window scene and
        // SwiftUI presents it to deliver *every* incoming URL, including
        // claudebar://open. AppDelegate routes every URL, so this window
        // claims none: an empty set matches nothing.
        .handlesExternalEvents(matching: [])
    }

}

private func sessionPhaseColor(_ phase: Session.Phase) -> Color {
    phase.color
}

/// The menu bar icon that reflects the overall quota status.
/// When a Claude Code session is active, shows a terminal icon with phase color.
/// Uses theme's `statusBarIconName` if set, otherwise shows status-based icons.
struct StatusBarIcon: View {
    let status: QuotaStatus
    var activeSession: Session? = nil

    @Environment(\.appTheme) private var theme

    var body: some View {

        let _ = KitObservation.track()
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
