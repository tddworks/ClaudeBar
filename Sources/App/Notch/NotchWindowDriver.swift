import AppKit
import Domain
import Infrastructure

/// Keeps the notch in sync with the app's state.
///
/// Mirrors `StatusItemLabelDriver`: an `ObservationRenderSync` reads every
/// `@Observable` property the notch depends on and pushes the resolved activity
/// into the window controller. SwiftUI is not involved — the notch lives in its
/// own `NSPanel`, and `MenuBarExtra`'s hosting has a history of going quiet
/// after sleep (issue #192).
@MainActor
final class NotchWindowDriver {
    private let monitor: QuotaMonitor
    private let sessionMonitor: SessionMonitor
    private let settings: AppSettings
    private let controller = NotchWindowController()
    private let resolver = NotchActivityResolver()

    private var contentSync: ObservationRenderSync<NotchContent>?
    private var enabledSync: ObservationRenderSync<Bool>?
    private var launchObserver: NSObjectProtocol?

    /// Re-resolves the content at a moment nothing else will: the end of the
    /// "done" flash, or the end of a snooze.
    private var wakeTimer: Timer?

    /// While set, the notch stays retracted. Snoozing is time-boxed on purpose —
    /// a dismissal that never comes back is indistinguishable from a broken
    /// feature.
    private var snoozedUntil: Date?

    /// How long the snooze button silences the notch for.
    private static let snoozeDuration: TimeInterval = 30 * 60

    /// How long a finished session stays worth listing in the panel.
    private static let recentSessionWindow: TimeInterval = 10 * 60

    init(monitor: QuotaMonitor, sessionMonitor: SessionMonitor, settings: AppSettings) {
        self.monitor = monitor
        self.sessionMonitor = sessionMonitor
        self.settings = settings
    }

    /// Defers `start()` until the app has finished launching.
    ///
    /// `ClaudeBarApp` builds this driver in `App.init()`, and starting there
    /// would create an `NSWindow` and its `NSHostingView` before SwiftUI has
    /// built a single scene. Doing so left `MenuBarExtra`'s popover sized to
    /// roughly twice its content — 400x671 around 300pt of cards — for the
    /// life of the process, and switching the notch off afterwards did not
    /// undo it, because the damage was done at construction.
    func startWhenLaunched() {
        if NSApp?.isRunning == true {
            start()
            return
        }

        launchObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let observer = self.launchObserver {
                    NotificationCenter.default.removeObserver(observer)
                    self.launchObserver = nil
                }
                self.start()
            }
        }
    }

    /// Starts watching the setting, bringing the notch up and down with it.
    func start() {
        let sync = ObservationRenderSync<Bool>(
            read: { [settings] in settings.notchEnabled },
            render: { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    controller.start()
                    controller.setActions(
                        refresh: { [weak self] in self?.refreshQuotas() },
                        snooze: { [weak self] in self?.snooze() }
                    )
                    startContentSync()
                } else {
                    stopContentSync()
                    controller.stop()
                }
            }
        )
        enabledSync = sync
        sync.start()
    }

    // MARK: - Private

    private func startContentSync() {
        guard contentSync == nil else { return }

        let sync = ObservationRenderSync<NotchContent>(
            read: { [weak self] in self?.currentContent() ?? .empty },
            render: { [weak self] content in
                self?.controller.update(content: content)
                self?.scheduleWake(for: content.activity)
            }
        )
        contentSync = sync
        sync.start()
    }

    private func stopContentSync() {
        contentSync?.stop()
        contentSync = nil
        wakeTimer?.invalidate()
        wakeTimer = nil
    }

    /// Reads everything the notch depends on. Every `@Observable` property
    /// touched here is tracked, so any change re-resolves the content.
    ///
    /// Scoped to the provider selected in the popover. The notch is a second
    /// view onto that selection, not a separate one: showing an average across
    /// nineteen providers would report a number the user never chose to watch.
    private func currentContent() -> NotchContent {
        let now = Date()

        // A session that finished ten minutes ago is history, not status. Left
        // unfiltered it would sit in the panel for the rest of the day.
        let sessions = [sessionMonitor.activeSession].compactMap { $0 }
            + sessionMonitor.recentSessions.filter { session in
                guard let finishedAt = session.finishedAt else { return true }
                return now.timeIntervalSince(finishedAt) < Self.recentSessionWindow
            }

        let selected = monitor.selectedProvider
        let snapshot = selected?.snapshot
        let quotas = snapshot?.quotas ?? []
        let headline = snapshot?.lowestQuota

        var activity = resolver.resolve(
            sessions: sessions,
            quotas: quotas,
            headlineQuota: headline,
            now: now
        )
        if isSnoozed(at: now), !demandsAttentionThroughSnooze(activity) {
            activity = nil
        }

        return NotchContent(
            activity: activity,
            sessions: Array(sessions.prefix(3)),
            // The panel is about what is nearly gone, so lead with the most
            // depleted rather than whichever quota happens to be first.
            quotas: Array(quotas.sorted { $0.percentRemaining < $1.percentRemaining }.prefix(3)),
            today: snapshot?.dailyUsageReport?.today,
            headline: headline,
            isRefreshing: selected?.isSyncing ?? false
        )
    }

    /// Refreshes only what the notch is showing. Refreshing all nineteen
    /// providers to update one reading is work the user did not ask for, and
    /// leaves the loader stopping while other providers are still fetching.
    private func refreshQuotas() {
        let providerId = monitor.selectedProviderId
        Task { await monitor.refresh(providerId: providerId) }
    }

    private func snooze() {
        snoozedUntil = Date().addingTimeInterval(Self.snoozeDuration)
        contentSync?.refreshNow()
        scheduleWake(at: snoozedUntil)
    }

    private func isSnoozed(at now: Date) -> Bool {
        guard let snoozedUntil else { return false }
        if now >= snoozedUntil {
            self.snoozedUntil = nil
            return false
        }
        return true
    }

    /// A snooze quiets ambient status, not a session that is blocked on the
    /// user — that is the one thing worth interrupting for.
    private func demandsAttentionThroughSnooze(_ activity: NotchActivity?) -> Bool {
        if case .awaitingInput = activity { return true }
        return false
    }

    /// A finished session stops being worth showing on a clock, not on a state
    /// change — nothing will fire an observation to retract it, so schedule the
    /// re-resolve ourselves. Same for the end of a snooze.
    private func scheduleWake(for activity: NotchActivity?) {
        guard case .finished(let session) = activity, let finishedAt = session.finishedAt else {
            scheduleWake(at: snoozedUntil)
            return
        }
        scheduleWake(
            at: finishedAt.addingTimeInterval(NotchActivityResolver.defaultFinishedDisplayDuration)
        )
    }

    private func scheduleWake(at date: Date?) {
        wakeTimer?.invalidate()
        wakeTimer = nil

        guard let date else { return }
        let delay = date.timeIntervalSinceNow + 0.1
        guard delay > 0 else { return }

        wakeTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.contentSync?.refreshNow()
            }
        }
    }
}
