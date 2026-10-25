import AppKit
import SwiftUI

// MARK: - Window Visibility & Frame Ticker

private struct PopoverShownKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var isPopoverShown: Bool {
        get { self[PopoverShownKey.self] }
        set { self[PopoverShownKey.self] = newValue }
    }
}

/// Attaches a tiny `NSView` probe so `FrameClock` can directly inspect
/// `window?.isVisible` and wake up when the window is ordered back on screen.
struct WindowVisibilityObserver: NSViewRepresentable {
    let clock: FrameClock
    let onWindowEvent: () -> Void

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        clock.anchorView = view
        view.onWindowEvent = onWindowEvent
        return view
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        clock.anchorView = nsView
        nsView.onWindowEvent = onWindowEvent
    }

    @MainActor
    final class ProbeView: NSView {
        private var kvo: NSKeyValueObservation?
        nonisolated(unsafe) private var tokens: [NSObjectProtocol] = []
        var onWindowEvent: (() -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeObservers()
            kvo = window?.observe(\.isVisible, options: [.new]) { [weak self] _, _ in
                // AppKit normally delivers this on main. Handle that edge
                // immediately so a rapid reopen cannot strand a stopped clock
                // behind queued callbacks in a nested event loop.
                if Thread.isMainThread {
                    MainActor.assumeIsolated {
                        self?.onWindowEvent?()
                    }
                } else {
                    DispatchQueue.main.async { [weak self] in
                        MainActor.assumeIsolated {
                            self?.onWindowEvent?()
                        }
                    }
                }
            }
            if let window {
                let names: [Notification.Name] = [
                    NSWindow.didChangeOcclusionStateNotification,
                    NSWindow.didBecomeKeyNotification,
                    NSWindow.didResignKeyNotification,
                    NSWindow.didExposeNotification,
                ]
                for name in names {
                    let token = NotificationCenter.default.addObserver(
                        forName: name,
                        object: window,
                        queue: .main
                    ) { [weak self] _ in
                        MainActor.assumeIsolated {
                            self?.onWindowEvent?()
                        }
                    }
                    tokens.append(token)
                }
            }
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.onWindowEvent?()
                }
            }
        }

        private nonisolated func removeObservers() {
            for token in tokens {
                NotificationCenter.default.removeObserver(token)
            }
            tokens.removeAll()
        }

        deinit {
            removeObservers()
        }
    }
}

/// Discrete timer clock that ticks only while active and its hosting `NSWindow`
/// is visible, avoiding SwiftUI's continuous `ViewGraphRootValueUpdater`
/// display-cycle spin loop in borderless `MenuBarExtra` windows.
@MainActor
@Observable
final class FrameClock {
    var now = Date()
    @ObservationIgnored nonisolated(unsafe) private var timer: Timer?
    @ObservationIgnored private var currentInterval: TimeInterval?
    @ObservationIgnored weak var anchorView: NSView?

    private var isWindowVisible: Bool {
        guard let anchorView else { return true }
        return anchorView.window?.isVisible == true
    }

    func update(active: Bool, interval: TimeInterval) {
        guard active && isWindowVisible else {
            stop()
            return
        }
        guard timer == nil || currentInterval != interval else { return }
        stop()
        currentInterval = interval
        now = Date()
        let scheduled = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard self.isWindowVisible else {
                    self.stop()
                    return
                }
                self.now = Date()
            }
        }
        RunLoop.main.add(scheduled, forMode: .common)
        timer = scheduled
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        currentInterval = nil
    }

    deinit {
        timer?.invalidate()
    }
}

/// Drives periodic or frame-rate view updates while the hosting window is
/// visible and `paused` is `false`, stopping completely when the popover closes
/// (`orderOut`) or when paused.
struct WindowFrameTicker<Content: View>: View {
    let interval: TimeInterval
    var paused: Bool = false
    @ViewBuilder let content: (Date) -> Content

    @Environment(\.isPopoverShown) private var isPopoverShown
    @State private var clock = FrameClock()

    private var isActive: Bool {
        !paused && isPopoverShown
    }

    var body: some View {
        content(clock.now)
            .background(
                WindowVisibilityObserver(clock: clock) {
                    clock.update(active: isActive, interval: interval)
                }
            )
            .onAppear {
                clock.update(active: isActive, interval: interval)
            }
            .onDisappear {
                clock.stop()
            }
            .onChange(of: isActive) { _, active in
                clock.update(active: active, interval: interval)
            }
            .onChange(of: interval) { _, newInterval in
                clock.update(active: isActive, interval: newInterval)
            }
    }
}
