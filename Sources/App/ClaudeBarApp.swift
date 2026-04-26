import SwiftUI
import Domain
import Infrastructure
import Combine
import UserNotifications
#if ENABLE_SPARKLE
import Sparkle
#endif

extension Notification.Name {
    static let hookSettingsChanged = Notification.Name("com.tddworks.claudebar.hookSettingsChanged")
}

// MARK: - App Entry Point

@main
struct ClaudeBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    /// The main domain service - monitors all AI providers
    private(set) var monitor: QuotaMonitor!

    /// Monitors Claude Code sessions via hook events
    private(set) var sessionMonitor: SessionMonitor!

    /// The hook HTTP server that receives events from Claude Code
    private let hookServer = HookHTTPServer()

    /// Task for the hook server event loop
    private var hookServerTask: Task<Void, Never>?

    /// Alerts users when quota status degrades
    private let quotaAlerter = NotificationAlerter()

    /// Sends session start/end notifications
    private let sessionAlertSender = SystemAlertSender()

    #if ENABLE_SPARKLE
    /// Sparkle updater for auto-updates
    private(set) var sparkleUpdater: SparkleUpdater?
    #endif

    /// Combine subscriptions for observing model changes
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        AppLog.ui.info("ClaudeBar v\(version) (\(build)) initializing...")

        // Create the shared settings repository (JSON-backed: ~/.claudebar/settings.json)
        let settingsRepository = JSONSettingsRepository.shared

        // Create all providers with their probes (rich domain models)
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
        monitor = QuotaMonitor(
            providers: repository,
            alerter: quotaAlerter,
            clock: SystemClock()
        )
        AppLog.monitor.info("QuotaMonitor initialized")

        // Initialize session monitor
        sessionMonitor = SessionMonitor()

        #if ENABLE_SPARKLE
        sparkleUpdater = SparkleUpdater()
        #endif

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

        // Set up status bar
        setupStatusBar()

        // Observe model changes to update status bar icon
        observeModelChanges()

        // Request notification permission
        requestNotificationPermission()

        AppLog.ui.info("ClaudeBar initialization complete")
    }

    // MARK: - Status Bar Setup

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = statusBarImage(for: .healthy)
            button.action = #selector(togglePopover)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover = NSPopover()
        popover?.behavior = .transient

        var contentView: AnyView = AnyView(MenuContentView(
            monitor: monitor,
            sessionMonitor: sessionMonitor,
            quotaAlerter: quotaAlerter
        ) { [weak self] enabled in
            if enabled { self?.startHookServer() } else { self?.stopHookServer() }
        }
        .environmentObject(AppSettings.shared)
        .appThemeProvider(themeModeId: AppSettings.shared.themeMode))

        #if ENABLE_SPARKLE
        if let sparkleUpdater = sparkleUpdater {
            contentView = AnyView(contentView.environment(\.sparkleUpdater, sparkleUpdater))
        }
        #endif

        popover?.contentViewController = NSHostingController(rootView: contentView)
    }

    // MARK: - Popover Toggle

    @objc private func togglePopover() {
        guard let popover = popover, let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Update theme when opening
            if let vc = popover.contentViewController as? NSHostingController<AnyView> {
                let settings = AppSettings.shared
                var rootView: AnyView = AnyView(MenuContentView(
                    monitor: monitor,
                    sessionMonitor: sessionMonitor,
                    quotaAlerter: quotaAlerter
                ) { [weak self] enabled in
                    if enabled { self?.startHookServer() } else { self?.stopHookServer() }
                }
                .environmentObject(settings)
                .appThemeProvider(themeModeId: settings.themeMode))

                #if ENABLE_SPARKLE
                if let sparkleUpdater = sparkleUpdater {
                    rootView = AnyView(rootView.environment(\.sparkleUpdater, sparkleUpdater))
                }
                #endif

                vc.rootView = rootView
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            constrainPopoverToScreen()
        }
    }

    /// Clamp popover position so it stays within visible screen bounds (macOS 12 fix).
    private func constrainPopoverToScreen() {
        guard let popover = popover,
              let window = popover.contentViewController?.view.window,
              let screen = window.screen ?? NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let windowFrame = window.frame

        if windowFrame.maxX > screenFrame.maxX {
            let shift = windowFrame.maxX - screenFrame.maxX
            window.setFrameOrigin(NSPoint(x: windowFrame.origin.x - shift, y: windowFrame.origin.y))
        }
        if windowFrame.maxY > screenFrame.maxY {
            let shift = windowFrame.maxY - screenFrame.maxY
            window.setFrameOrigin(NSPoint(x: windowFrame.origin.x, y: windowFrame.origin.y - shift))
        }
    }

    // MARK: - Model Change Observation

    private func observeModelChanges() {
        // Update status bar icon when provider state changes
        monitor.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusBarIcon()
            }
            .store(in: &cancellables)

        sessionMonitor.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusBarIcon()
            }
            .store(in: &cancellables)

        AppSettings.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusBarIcon()
            }
            .store(in: &cancellables)
    }

    private func updateStatusBarIcon() {
        guard let snapshot = monitor?.selectedProvider?.snapshot else {
            statusItem?.button?.image = statusBarImage(for: .healthy)
            return
        }

        let settings = AppSettings.shared
        let status: QuotaStatus
        if settings.burnRateWarningEnabled {
            status = snapshot.paceAwareOverallStatus(burnRateThreshold: settings.burnRateThreshold)
        } else {
            status = snapshot.overallStatus
        }

        if let session = sessionMonitor?.activeSession {
            statusItem?.button?.image = sessionStatusBarImage(sessionPhase: session.phase, status: status)
        } else {
            statusItem?.button?.image = statusBarImage(for: status)
        }
    }

    // MARK: - Status Bar Images

    private func statusBarImage(for status: QuotaStatus) -> NSImage? {
        guard let theme = ThemeRegistry.shared.theme(for: AppSettings.shared.themeMode) else {
            return NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: String(describing: status))
        }

        let iconName: String
        if let themeIcon = theme.statusBarIconName {
            iconName = themeIcon
        } else {
            switch status {
            case .depleted: iconName = "chart.bar.xaxis"
            case .critical: iconName = "exclamationmark.triangle.fill"
            case .warning, .healthy: iconName = "chart.bar.fill"
            }
        }

        let color = NSColor(theme.statusColor(for: status))
        return NSImage(systemSymbolName: iconName, accessibilityDescription: String(describing: status))?
            .withSymbolConfiguration(.init(paletteColors: [color]))
    }

    private func sessionStatusBarImage(sessionPhase: ClaudeSession.Phase, status: QuotaStatus) -> NSImage? {
        let phaseColor = NSColor(sessionPhase.color)
        guard let theme = ThemeRegistry.shared.theme(for: AppSettings.shared.themeMode) else {
            return NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: "session")?
                .withSymbolConfiguration(.init(paletteColors: [phaseColor]))
        }
        let statusColor = NSColor(theme.statusColor(for: status))

        let terminalImage = NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: "session")?
            .withSymbolConfiguration(.init(paletteColors: [phaseColor]))

        let statusIconName: String
        if let themeIcon = theme.statusBarIconName {
            statusIconName = themeIcon
        } else {
            switch status {
            case .depleted: statusIconName = "chart.bar.xaxis"
            case .critical: statusIconName = "exclamationmark.triangle.fill"
            case .warning, .healthy: statusIconName = "chart.bar.fill"
            }
        }

        let statusImage = NSImage(systemSymbolName: statusIconName, accessibilityDescription: String(describing: status))?
            .withSymbolConfiguration(.init(paletteColors: [statusColor]))

        return terminalImage ?? statusImage
    }

    // MARK: - Hook Server

    private func startHookServer() {
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

    // MARK: - Notification Permission

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}

// MARK: - PreviewProvider

struct StatusBarIcon_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 30) {
            VStack {
                Image(systemName: "chart.bar.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundColor(.green)
                Text("HEALTHY")
                    .font(.caption)
                    .foregroundColor(.green)
            }
            VStack {
                Image(systemName: "chart.bar.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundColor(.orange)
                Text("WARNING")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            VStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundColor(.red)
                Text("CRITICAL")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            VStack {
                Image(systemName: "chart.bar.xaxis")
                    .symbolRenderingMode(.palette)
                    .foregroundColor(.red)
                Text("DEPLETED")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(40)
        .background(Color.black)
    }
}
