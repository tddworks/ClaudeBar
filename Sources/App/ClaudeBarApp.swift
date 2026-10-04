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

@main
struct ClaudeBarApp: App {
    /// A built-in provider from its bundled definition. A definition that fails
    /// to load is a packaging bug the catalog tests catch before release.
    @MainActor
    private static func builtIn(
        _ id: String,
        settings: any MultiAccountSettingsRepository,
        accounts: [ProviderAccountConfig] = [],
        secrets: (any SecretVault)? = nil,
        guestPasses: GuestPasses? = nil,
        usageHistory: UsageHistory? = nil,
        environment: @escaping @Sendable (String) -> String? = { ProcessInfo.processInfo.environment[$0] }
    ) -> Provider {
        do {
            return try Providers.make(id, settings: settings, accounts: accounts, secrets: secrets, guestPasses: guestPasses,
                                      usageHistory: usageHistory, environment: environment)
        } catch {
            preconditionFailure("Built-in provider '\(id)' failed to load: \(error.localizedDescription)")
        }
    }

    /// The main domain service - monitors all AI providers
    /// This is the single source of truth for providers and their state
    @State private var monitor: QuotaMonitor

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

        // Claude is data: Modules/Providers/Resources/Providers/claude.json
        // and the mapping scripts beside it. Guest passes ride along, the
        // default login's. Logins added beside it live in their own config
        // folders.
        let claude = Self.builtIn(
            "claude",
            settings: settingsRepository,
            accounts: settingsRepository.accounts(forProvider: "claude"),
            // Guest passes run the same Claude CLI, at its CLI location (#210).
            guestPasses: GuestPasses(source: ClaudeGuestPassSource(
                claudeBinary: { settingsRepository.cliPath(forProvider: "claude") ?? "claude" }
            ))
        )
        // Codex is data: Modules/Providers/Resources/Providers/codex.json — the
        // product once, with the logins added beside the default one (#326).
        let codex = Self.builtIn("codex", settings: settingsRepository, accounts: settingsRepository.accounts(forProvider: "codex"))

        let vault = ProviderVault()
        // These are data: their keys, regions and environment variables are
        // settings in their JSON, so nothing here is theirs.
        let minimax = Self.builtIn("minimax", settings: settingsRepository,
                                   accounts: settingsRepository.accounts(forProvider: "minimax"), secrets: vault)
        let vercel = Self.builtIn("vercel-gateway", settings: settingsRepository,
                                  accounts: settingsRepository.accounts(forProvider: "vercel-gateway"), secrets: vault)
        let commandCode = Self.builtIn("commandcode", settings: settingsRepository,
                                       accounts: settingsRepository.accounts(forProvider: "commandcode"), secrets: vault)
        let amp = Self.builtIn("ampcode", settings: settingsRepository,
                               accounts: settingsRepository.accounts(forProvider: "ampcode"), secrets: vault)
        let kiro = Self.builtIn("kiro", settings: settingsRepository,
                                accounts: settingsRepository.accounts(forProvider: "kiro"), secrets: vault)
        let cursor = Self.builtIn("cursor", settings: settingsRepository,
                                  accounts: settingsRepository.accounts(forProvider: "cursor"), secrets: vault)
        let grok = Self.builtIn("grok", settings: settingsRepository,
                                accounts: settingsRepository.accounts(forProvider: "grok"), secrets: vault)
        let copilot = Self.builtIn("copilot", settings: settingsRepository,
                                   accounts: settingsRepository.accounts(forProvider: "copilot"), secrets: vault)
        let alibaba = Self.builtIn("alibaba", settings: settingsRepository,
                                   accounts: settingsRepository.accounts(forProvider: "alibaba"), secrets: vault)
        let gemini = Self.builtIn("gemini", settings: settingsRepository,
                                  accounts: settingsRepository.accounts(forProvider: "gemini"))
        let antigravity = Self.builtIn("antigravity", settings: settingsRepository)
        // Bedrock's metrics and prices come from the AWS SDK, linked by AWSClients alone.
        let bedrock: Provider = {
            do {
                return try Providers.make("bedrock", settings: settingsRepository,
                                          cloudWatch: AWSClients.makeCloudWatch(), priceCatalog: AWSClients.makePriceCatalog())
            } catch {
                preconditionFailure("Built-in provider 'bedrock' failed to load: \(error.localizedDescription)")
            }
        }()
        let omp = Self.builtIn("omp", settings: settingsRepository)
        let mistral = Self.builtIn("mistral", settings: settingsRepository)
        let kimi = Self.builtIn("kimi", settings: settingsRepository,
                                accounts: settingsRepository.accounts(forProvider: "kimi"), secrets: vault)
        let openCodeGo = Self.builtIn("opencode-go", settings: settingsRepository,
                                      accounts: settingsRepository.accounts(forProvider: "opencode-go"), secrets: vault)

        // Keep the existing default login's configurable environment name until
        // provider settings forms move to definitions. Added logins use only
        // their own saved key, as deepseek.json's accounts.patch declares.
        // A variable the person named for Z.ai is also read from their login
        // shell (#170). Z.ai reads it last, after the saved key and Claude
        // Code's settings, and no one else's lookup waits for a shell.
        let shellEnvironment = ShellEnvironment()
        let zai = Self.builtIn("zai", settings: settingsRepository,
                               accounts: settingsRepository.accounts(forProvider: "zai"), secrets: vault,
                               environment: { name in
            let named = settingsRepository.value("glmAuthEnvVar", forProvider: "zai")
            return name == named ? shellEnvironment.value(name) : ProcessInfo.processInfo.environment[name]
        })
        let deepseek = Self.builtIn("deepseek", settings: settingsRepository,
                                   accounts: settingsRepository.accounts(forProvider: "deepseek"), secrets: vault,
                                   environment: { name in
            let configured = settingsRepository.deepseekAuthEnvVar()
            let variable = name == "DEEPSEEK_API_KEY" && !configured.isEmpty ? configured : name
            return ProcessInfo.processInfo.environment[variable]
        })

        // The lineup: each login is its own pill. Legacy providers are their
        // own single login until they become definitions.
        // Each provider manages its own isEnabled state (persisted via ProviderSettingsRepository)
        let repository = AIProviders(providers: [
            claude.defaultAccount,
            codex.defaultAccount,
            gemini.defaultAccount,
            antigravity.defaultAccount,
            zai.defaultAccount,
            copilot.defaultAccount,
            bedrock.defaultAccount,
            amp.defaultAccount,
            kimi.defaultAccount,
            kiro.defaultAccount,
            cursor.defaultAccount,
            minimax.defaultAccount,
            deepseek.defaultAccount,
            vercel.defaultAccount,
            alibaba.defaultAccount,
            mistral.defaultAccount,
            openCodeGo.defaultAccount,
            omp.defaultAccount,
            grok.defaultAccount,
            commandCode.defaultAccount,
        ])
        // Added logins follow the built-in lineup, as they always have.
        for account in (claude.accounts + codex.accounts + minimax.accounts + deepseek.accounts + vercel.accounts + commandCode.accounts + amp.accounts + kiro.accounts + cursor.accounts + grok.accounts + openCodeGo.accounts + zai.accounts + kimi.accounts + copilot.accounts + alibaba.accounts + gemini.accounts).filter({ !$0.isDefault }) {
            repository.add(account)
        }
        // Providers people made in Add Provider (~/.claudebar/providers), after
        // the built-ins; their keys come from ClaudeBar's vault.
        for definition in ProviderCatalog().custom() {
            Providers.register(custom: definition)
            let custom = Providers.make(definition, settings: settingsRepository,
                                        accounts: settingsRepository.accounts(forProvider: definition.id), secrets: vault)
            for account in custom.accounts { repository.add(account) }
        }
        AppLog.providers.info("Created \(repository.all.count) providers")

        // Initialize the domain service with quota alerter
        // QuotaMonitor automatically validates selected provider on init
        // The settings repository carries the user's provider order (issue #141),
        // so the popover, overview and ⌘1–⌘9 follow it.
        // Alerts and every status follow the person's burn-rate setting (#357).
        // Hidden quotas (#140) are read from the same settings, per product.
        let monitor = QuotaMonitor(
            providers: repository,
            alerter: quotaAlerter,
            settingsRepository: settingsRepository,
            statusPolicy: { AppSettings.shared.statusPolicy }
        )
        self.monitor = monitor
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

        // Load user extensions from ~/.claudebar/extensions/
        let extensionRegistry = ExtensionRegistry(
            settingsRepository: settingsRepository,
            configRepository: AppSettings.shared.extensionConfig
        )
        let extensionProviders = extensionRegistry.loadExtensions(into: monitor)
        ProviderVisualIdentityLookup.registerExtensionIcons(from: extensionProviders)
        if !extensionProviders.isEmpty {
            AppLog.providers.info("Loaded \(extensionProviders.count) extension provider(s): \(extensionProviders.map(\.name).joined(separator: ", "))")
        }

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
        }
    }

    var body: some Scene {
        MenuBarExtra {
            Group {
                #if ENABLE_SPARKLE
                MenuContentView(monitor: monitor, sessionMonitor: sessionMonitor, quotaAlerter: quotaAlerter, onClose: { isMenuPresented = false }) { enabled in
                        if enabled { startHookServer() } else { stopHookServer() }
                    }
                    .appThemeProvider(themeModeId: settings.themeMode)
                    .environment(\.sparkleUpdater, sparkleUpdater)
                #else
                MenuContentView(monitor: monitor, sessionMonitor: sessionMonitor, quotaAlerter: quotaAlerter, onClose: { isMenuPresented = false }) { enabled in
                        if enabled { startHookServer() } else { stopHookServer() }
                    }
                    .appThemeProvider(themeModeId: settings.themeMode)
                #endif
            }
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
                SettingsWindowView(monitor: monitor, notifyDriver: notifyDriver) { enabled in
                    if enabled { startHookServer() } else { stopHookServer() }
                }
                .appThemeProvider(themeModeId: settings.themeMode)
                .environment(\.sparkleUpdater, sparkleUpdater)
                #else
                SettingsWindowView(monitor: monitor, notifyDriver: notifyDriver) { enabled in
                    if enabled { startHookServer() } else { stopHookServer() }
                }
                .appThemeProvider(themeModeId: settings.themeMode)
                #endif
            }
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
