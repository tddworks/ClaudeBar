import Dispatch
import Foundation
import Kit

/// Coalesces writes into the menu bar's status item: at most one actual write
/// per minimum interval, with a guaranteed trailing flush of the latest
/// content.
///
/// The status item's button is backed by the system's Control Center
/// status-items XPC service, and on macOS 26.6 a rapid stream of updates into
/// that service can abort inside Apple's own serializer, taking the whole app
/// down and leaving no menu bar item behind (issue #281). The countdown blink
/// re-rendered the label up to twice a second — exactly such a stream. The
/// gate collapses that cadence: the first write goes out immediately, renders
/// arriving inside the window only replace the single pending content, and one
/// trailing flush, scheduled for the remainder of the window, publishes the
/// final content. A flush is scheduled at most once per window, so the write
/// rate is bounded no matter how fast renders arrive.
///
/// The countdown tick runs at the same one-second rate as the gate, so the
/// alternating blink phases land on window boundaries and keep alternating
/// (a 0.5s tick under this gate would collapse every bright phase into the
/// dim one). The tick is what re-reads the wall clock, so a countdown still
/// advances within about a second of the true minute boundary.
///
/// Time and scheduling are injected so tests can drive the clock manually;
/// production uses a monotonic clock (`StatusItemClock.monotonicNow`) and a
/// one-shot main-runloop timer.
///
/// Tests: `Tests/AppTests/StatusItem/StatusItemWriteGateTests.swift`. They
/// verify the update-rate reduction, not the Apple-side abort, which cannot
/// be reproduced in a unit test.

/// Time sources for the status-item write gate.
enum StatusItemClock {
    /// Production time source: the process's monotonic uptime. Unlike the
    /// wall clock it never jumps — a user or time zone change cannot make a
    /// submit interval come out negative (flooding writes) or huge (deferring
    /// the trailing flush for ages). The countdown's visible value still
    /// reads the wall clock, in the driver, where the label is drawn.
    static func monotonicNow() -> TimeInterval {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }
}

@MainActor
final class StatusItemWriteGate<Content: Equatable> {
    /// Reads the current time, in seconds, on whatever scale `now` provides.
    typealias Now = @MainActor () -> TimeInterval

    /// Schedules `fire` to run after `delay`. Production adds a one-shot timer
    /// to the main runloop; tests capture and fire manually.
    typealias Scheduler = @MainActor (
        _ delay: TimeInterval,
        _ fire: @escaping @MainActor @Sendable () -> Void
    ) -> Void

    private let minimumInterval: TimeInterval
    private let rateWindow: TimeInterval
    private let now: Now
    private let schedule: Scheduler
    private let write: @MainActor (Content) -> Void

    /// Time of the last actual write; nil until the first one.
    private var lastWriteAt: TimeInterval?
    /// The latest content held back inside the current window.
    private var pending: Content?
    private var isFlushScheduled = false
    /// Incremented whenever an armed flush schedule is retired, so a
    /// late-firing schedule can recognize it is no longer the current one.
    private var flushGeneration = 0

    // Rate counters for the debug log below. Counts only — content values
    // never enter the log (the file log has no privacy redaction).
    private var windowStart: TimeInterval
    private var windowWrites = 0
    private var windowCoalesced = 0

    init(
        minimumInterval: TimeInterval,
        rateWindow: TimeInterval = 60,
        now: @escaping Now = StatusItemClock.monotonicNow,
        schedule: @escaping Scheduler = StatusItemWriteGate.scheduleOnMainRunLoop,
        write: @escaping @MainActor (Content) -> Void
    ) {
        self.minimumInterval = minimumInterval
        self.rateWindow = rateWindow
        self.now = now
        self.schedule = schedule
        self.write = write
        self.windowStart = now()
    }

    /// Submits one render for publication. The first write goes out
    /// immediately; a render inside the window replaces the pending content
    /// and is published by the trailing flush instead.
    func submit(_ content: Content) {
        let currentNow = now()
        if let lastWriteAt, currentNow - lastWriteAt < minimumInterval {
            pending = content
            windowCoalesced += 1
            guard !isFlushScheduled else { return }
            isFlushScheduled = true
            let generation = flushGeneration
            schedule(minimumInterval - (currentNow - lastWriteAt)) { [weak self] in
                self?.flushPending(ifStillScheduled: generation)
            }
            return
        }
        retireFlushSchedule()
        performWrite(content, at: currentNow)
    }

    /// The trailing flush. Runs when the scheduled remainder of the window has
    /// elapsed — later is safe (the pending content is still current), and
    /// early is impossible because the delay is the exact remainder. Internal
    /// so tests can fire the trailing edge without a scheduler.
    func flushPending() {
        isFlushScheduled = false
        guard let pending else { return }
        performWrite(pending, at: now())
    }

    /// The scheduled callback's entry point: a no-op unless its schedule is
    /// still the armed one. A schedule retired by an immediate write must not
    /// write — its pending content and window are stale, and writing could
    /// land inside the next write's interval (issue #281 review).
    private func flushPending(ifStillScheduled generation: Int) {
        guard generation == flushGeneration else { return }
        flushPending()
    }

    /// Invalidates the armed flush schedule, if any. The underlying timer
    /// cannot be cancelled from here (the scheduler returns no handle), so
    /// retirement bumps the generation and lets the callback no-op itself.
    private func retireFlushSchedule() {
        guard isFlushScheduled else { return }
        isFlushScheduled = false
        flushGeneration += 1
    }

    /// Replaces the pending content of the currently armed flush without
    /// scheduling anything or writing. The driver calls this from the render
    /// skip path: the screen already shows the newest render, so any flush
    /// still armed from an earlier render would otherwise publish a value
    /// older than what is visible. A no-op when nothing is pending.
    func reconcile(_ content: Content) {
        guard pending != nil else { return }
        pending = content
    }

    private func performWrite(_ content: Content, at currentNow: TimeInterval) {
        pending = nil
        lastWriteAt = currentNow
        logRateIfNeeded(at: currentNow)
        write(content)
    }

    /// One debug line per rate window — writes and coalesced submissions — so
    /// a future crash report can be correlated with the status-item update
    /// rate (issue #281). Counts only, never content values. `debug` goes to
    /// OSLog only, so this costs nothing in the file log.
    private func logRateIfNeeded(at currentNow: TimeInterval) {
        windowWrites += 1
        guard currentNow - windowStart >= rateWindow else { return }
        AppLog.ui.debug(
            "Status item: \(self.windowWrites) writes, \(self.windowCoalesced) coalesced in the last \(Int(self.rateWindow))s"
        )
        windowStart = currentNow
        windowWrites = 0
        windowCoalesced = 0
    }

    /// One-shot timer on the main runloop, in `.common` so an open menu
    /// (tracking mode) cannot stall the trailing edge. The block hops back to
    /// the main actor the same way the countdown tick does.
    private static func scheduleOnMainRunLoop(
        _ delay: TimeInterval,
        _ fire: @escaping @MainActor @Sendable () -> Void
    ) {
        let timer = Timer(timeInterval: delay, repeats: false) { _ in
            MainActor.assumeIsolated {
                fire()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}
