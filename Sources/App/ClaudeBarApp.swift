import SwiftUI
import Domain
import Infrastructure
import Providers
import AWSClients
import MenuBarExtraAccess
#if ENABLE_SPARKLE
import Sparkle
#endif

extension Notification.Name {
    static let hookSettingsChanged = Notification.Name("com.tddworks.claudebar.hookSettingsChanged")

    /// Posted by the Notify! pane when the device link or a stored surface
    /// handle changes. Those live outside observable state, so nothing the
    /// publish driver watches would otherwise tell it to try again.
    static let notifySettingsChanged = Notification.Name("com.tddworks.claudebar.notifySettingsChanged")
}

/// Started by `ClaudeBarMain` — never while it hosts tests (see `LaunchMode`).
struct ClaudeBarApp: App {
    /// The main domain service - monitors all AI providers
    /// This is the single source of truth for providers and their state
    @State private var monitor: QuotaMonitor

    /// *New terminal sessions* — which login `claude` / `codex` start with.
    @State private var newSessions: NewSessions

    /// *Quota alerts* — the person's own percentages (#68).
    @State private var quotaAlerts: QuotaAlerts

    /// Monitors Claude Code sessions via hook events
    @State private var sessionMonitor: SessionMonitor

    /// Drives the menu-bar pixels and the background-refresh lifecycle
    /// imperatively, outside SwiftUI — the MenuBarExtra label hosting can
    /// permanently stop re-evaluating after system sleep (issue #192).
    private let statusItemDriver: StatusItemLabelDriver

    /// Draws Claude Code session and quota state into the notch. Comes up and
    /// goes down with `app.notchEnabled`; does nothing until it is turned on.
    private let notchDriver: NotchWindowDriver

    /// Exports quota and menu-bar status to ~/.claudebar/status.json for Touch Bar, BTT, and external scripts.
    private let statusExportDriver: StatusExportDriver
    /// Publishes quota state to a linked Notify! device. Comes up and goes down
    /// with `notify.enabled`; does nothing until a device is linked.
    private let notifyDriver: NotifyPublishDriver
    private let leaderboard: Leaderboard

    /// Binding required by `.menuBarExtraAccess`; also enables programmatic
    /// dropdown control if ever needed.
    @State private var isMenuPresented = false

    @Environment(\.openWindow) private var openWindow

    /// Receives `claudebar://` URLs. Lives outside SwiftUI's scene routing,
    /// which cannot reach a MenuBarExtra (see AppDelegate).
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// The hook HTTP server that receives events from Claude Code
    private let hookServer = HookHTTPServer()

    /// Task for the hook server event loop (allows cancellation on toggle off)
    @State private var hookServerTask: Task<Void, Never>?

    /// Alerts users when quota status degrades
    private let quotaAlerter = NotificationAlerter(accountSettings: JSONSettingsRepository.shared)

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

        // Every provider is a definition on disk — the bundle, Add Provider's
        // ~/.claudebar/providers and ~/.claudebar/extensions — found by the
        // catalog and made on one engine; no line here names a provider
        // (TARGET_ARCHITECTURE §10). The engine is everything that touches
        // this Mac: a definition uses what its cases ask for.
        let vault = ProviderVault()
        // A variable exported only in the login shell (#170), for a lookup that says `loginShell`.
        let shellEnvironment = ShellEnvironment()
        let engine = Engine(
            settings: settingsRepository,
            vault: vault,
            loginsInUse: DiskLoginsInUse(),
            loginShell: { shellEnvironment.value($0) },
            // The AWS SDK, linked by AWSClients alone, made once for a definition that reads the cloud.
            cloud: { (AWSClients.makeCloudWatch(), AWSClients.makePriceCatalog()) },
            // Guest passes run the declaring definition's CLI, at its CLI location (#210).
            guestPasses: { cli in ClaudeGuestPassSource(claudeBinary: cli) }
        )
        let definitions = ProviderCatalog().detect()
        // What was saved for an extension before it was a definition moves once.
        ExtensionSettingsUpgrade.run(definitions.filter { $0.profile.origin == .extension },
                                     store: .shared, settings: settingsRepository, vault: vault)
        // The products, in lineup order; each holds its logins, and the
        // lineup is the enabled logins of enabled products (CANONICAL §1).
        let providers = ProviderFactory.make(definitions, engine: engine)
        AppLog.providers.info("Created \(providers.count) providers")

        // *In use*: every product whose definition declares it — chosen by the
        // definition, never by a provider's name (CANONICAL §2.1).
        let products = providers
        let newSessions = NewSessions(products: products,
                                      shellLines: ShellSetup(commands: products.compactMap { $0.inUse?.command }),
                                      announcer: InUseNotifications())
        self.newSessions = newSessions

        // Initialize the domain service with quota alerter
        // QuotaMonitor automatically validates selected provider on init
        // The settings repository carries the user's provider order (issue #141),
        // so the popover, overview and ⌘1–⌘9 follow it.
        // Alerts and every status follow the person's burn-rate setting (#357).
        // Hidden quotas (#140) are read from the same settings, per product.
        let monitor = QuotaMonitor(
            providers: Providers(providers, settings: settingsRepository, vault: vault, make: { definition in
                ProviderFactory.make(definition, engine: engine)
            }),
            alerter: quotaAlerter,
            settingsRepository: settingsRepository,
            statusPolicy: { AppSettings.shared.statusPolicy }
        )
        self.monitor = monitor
        // *In use* follows every refresh: Switch when low, or a login worth moving to.
        monitor.onRefreshed { refreshed in await newSessions.review(refreshed) }
        // *Quota alerts* follow every refresh too, on what the person sees.
        let quotaAlerts = QuotaAlerts(settings: settingsRepository, announcer: QuotaAlertNotifications())
        self.quotaAlerts = quotaAlerts
        monitor.onRefreshed { [weak monitor] refreshed in
            guard let monitor else { return }
            await quotaAlerts.review(refreshed.id, named: monitor.lineupName(of: refreshed), usage: monitor.usage(of: refreshed))
        }
        AppLog.monitor.info("QuotaMonitor initialized")

        let sessionMonitor = SessionMonitor()
        self.sessionMonitor = sessionMonitor

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
        // Started here rather than deferred to `didFinishLaunching` like the
        // notch driver: the surface it drives is on the user's phone, so it
        // touches no AppKit window and has nothing to wait for.
        notifyDriver = NotifyPublishDriver(
            monitor: monitor,
            settings: AppSettings.shared
        )
        notifyDriver.start()

        // Uploads only once the user joined; until then it reads nothing.
        leaderboard = Leaderboard(monitor: monitor)
        leaderboard.start()

        // Start hook server if hooks are enabled
        if settingsRepository.isHookEnabled() {
            // Reconcile installed hooks so newly-added events (e.g.
            // UserPromptSubmit, which revives a stopped session) register for
            // existing users without re-toggling the setting. install() is
            // idempotent — it replaces only ClaudeBar's own matcher entries
            // per event and preserves hooks from other tools.
            if HookInstaller.isInstalled() {
                try? HookInstaller.install()
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

    private func startHookServer() {
        // Cancel any existing server task
        hookServerTask?.cancel()
        hookServer.stop()

        hookServerTask = Task {
            do {
                let events = try await hookServer.start()
                AppLog.hooks.info("Hook server started, listening for events")
                for await event in events {
                    // Ignore ClaudeBar's own background quota probe so routine
                    // polling doesn't spam "Claude Code Finished: Probe"
                    // notifications or pollute the recent-sessions list. (issue #172)
                    guard !event.isClaudeBarProbe else { continue }
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

    @MainActor
    private func handle(_ action: URLSchemeAction) {
        switch action {
        case .refresh:
            Task {
                await monitor.refreshAll()
            }
        case .open:
            isMenuPresented = true
            NSApp.activate(ignoringOtherApps: true)
        case .settings:
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        case let .use(providerId, name):
            switch newSessions.use(providerId: providerId, account: name) {
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
                SettingsWindowView(monitor: monitor, notifyDriver: notifyDriver, leaderboard: leaderboard) { enabled in
                    if enabled { startHookServer() } else { stopHookServer() }
                }
                .appThemeProvider(themeModeId: settings.themeMode)
                .environment(\.sparkleUpdater, sparkleUpdater)
                #else
                SettingsWindowView(monitor: monitor, notifyDriver: notifyDriver, leaderboard: leaderboard) { enabled in
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
