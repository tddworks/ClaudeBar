import SwiftUI
import Testing
@testable import ClaudeBar

/// Popover animations and timelines must rest while the popover window is closed
/// (`orderOut`) or idle, so the app uses no CPU in the background.
@MainActor
@Suite(.serialized)
struct WindowFrameTickerTests {
    /// This is deliberately not observable: recording a frame must never
    /// invalidate the view whose clock the test is measuring.
    private final class FrameSamples {
        private(set) var latest: Date?
        private(set) var count = 0

        func record(_ date: Date) {
            guard date != latest else { return }
            latest = date
            count += 1
        }
    }

    private struct FrameProbe: NSViewRepresentable {
        let samples: FrameSamples
        let date: Date

        func makeNSView(context: Context) -> NSView {
            samples.record(date)
            return NSView()
        }

        func updateNSView(_ view: NSView, context: Context) {
            samples.record(date)
        }
    }

    @Observable
    final class TickerState {
        var paused = false
        var isPopoverShown = true
    }

    private struct TickerHarness: View {
        let state: TickerState
        let samples: FrameSamples

        var body: some View {
            WindowFrameTicker(interval: 0.02, paused: state.paused) { date in
                FrameProbe(samples: samples, date: date)
                    .frame(width: 40, height: 40)
            }
            .environment(\.isPopoverShown, state.isPopoverShown)
        }
    }

    private func tickerWindow(state: TickerState, samples: FrameSamples) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 40, height: 40),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: TickerHarness(state: state, samples: samples))
        window.orderFrontRegardless()
        return window
    }

    private func waitForFrames(_ samples: FrameSamples, after count: Int) -> Bool {
        let deadline = Date().addingTimeInterval(0.5)
        while samples.count < count + 2, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        return samples.count >= count + 2
    }

    private func expectStopped(_ samples: FrameSamples, sourceLocation: SourceLocation = #_sourceLocation) {
        // Let the visibility/environment change finish rendering before
        // measuring; a final frame from that transition is not a running clock.
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let count = samples.count
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        #expect(samples.count == count, sourceLocation: sourceLocation)
    }

    @Test func `should resume advancing frames when a hidden window is shown again`() {
        let samples = FrameSamples()
        let window = tickerWindow(state: TickerState(), samples: samples)
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        #expect(waitForFrames(samples, after: samples.count))
        window.orderOut(nil)
        expectStopped(samples)

        let hiddenCount = samples.count
        window.orderFrontRegardless()
        #expect(window.isVisible)
        #expect(waitForFrames(samples, after: hiddenCount))
    }

    @Test func `should stop advancing frames while paused and resume when unpaused`() {
        let state = TickerState()
        let samples = FrameSamples()
        let window = tickerWindow(state: state, samples: samples)
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        #expect(waitForFrames(samples, after: samples.count))
        state.paused = true
        expectStopped(samples)

        let pausedCount = samples.count
        state.paused = false
        #expect(waitForFrames(samples, after: pausedCount))
    }

    @Test func `should stop advancing frames while the popover is closed even when its window is visible`() {
        let state = TickerState()
        let samples = FrameSamples()
        let window = tickerWindow(state: state, samples: samples)
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        #expect(waitForFrames(samples, after: samples.count))
        state.isPopoverShown = false
        expectStopped(samples)
        #expect(window.isVisible)

        let closedCount = samples.count
        state.isPopoverShown = true
        #expect(waitForFrames(samples, after: closedCount))
    }

    private final class CountingHostingView<Content: View>: NSHostingView<Content> {
        var layoutCount = 0
        override func layout() {
            layoutCount += 1
            super.layout()
        }
    }

    @Observable
    final class SyncState {
        var isSyncing = true
    }

    struct SyncHarness: View {
        let state: SyncState
        var body: some View {
            VStack(spacing: 0) {
                PulsingStatusDot(color: .green, isSyncing: state.isSyncing)
                QuestionBlockButton(isSyncing: state.isSyncing, action: {})
                ScrollView(.vertical, showsIndicators: false) {
                    Text(state.isSyncing ? "Syncing" : "Idle")
                        .frame(height: 40)
                }
                .frame(maxHeight: 560)
            }
            .frame(width: 380)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @Test func `should stop laying out the runner once the popover window closes`() throws {
        let runner = try #require(PlatformerTheme().runner)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 140),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let hosting = CountingHostingView(
            rootView: GroundRunnerView(runner: runner, status: .warning, isSyncing: false, floorHeight: 36)
        )
        window.contentView = hosting
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))

        // MenuBarExtra(.window) closes its popover with orderOut(nil), which does
        // not fire SwiftUI's .onDisappear.
        window.orderOut(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hosting.layoutCount = 0
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))

        #expect(hosting.layoutCount == 0)
    }

    @Test func `should stop laying out sync indicators while the popover window is closed`() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let hosting = CountingHostingView(
            rootView: VStack(spacing: 0) {
                PulsingStatusDot(color: .green, isSyncing: true)
                QuestionBlockButton(isSyncing: true, action: {})
                ScrollView(.vertical, showsIndicators: false) {
                    Text("Quota card")
                        .frame(height: 40)
                }
                .frame(maxHeight: 560)
            }
            .frame(width: 380)
            .fixedSize(horizontal: false, vertical: true)
        )
        window.contentView = hosting
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))

        window.orderOut(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hosting.layoutCount = 0
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))

        #expect(hosting.layoutCount == 0)
    }

    @Test func `should keep layout passes bounded while syncing and stop once syncing finishes`() {
        let state = SyncState()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let hosting = CountingHostingView(rootView: SyncHarness(state: state))
        window.contentView = hosting
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        hosting.layoutCount = 0
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        // At 30 FPS across two indicators in 0.2s, layout passes stay in single
        // or low double digits rather than spinning thousands of times per second.
        #expect(hosting.layoutCount <= 20)

        state.isSyncing = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hosting.layoutCount = 0
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))

        #expect(hosting.layoutCount == 0)
    }

    @Test func `should stop laying out the status dot when its window closes during a refresh`() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let hosting = CountingHostingView(
            rootView: VStack {
                PulsingStatusDot(color: .green, isSyncing: true)
                ScrollView {
                    Text("Quota card").frame(height: 40)
                }
                .frame(maxHeight: 560)
            }
            .frame(width: 380)
            .fixedSize(horizontal: false, vertical: true)
        )
        window.contentView = hosting
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))

        hosting.layoutCount = 0
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        #expect(hosting.layoutCount <= 20)

        window.orderOut(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hosting.layoutCount = 0
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        #expect(hosting.layoutCount == 0)
    }

    @Test func `should keep loading and sync indicators still with Reduce Motion`() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let hosting = CountingHostingView(
            rootView: VStack {
                LoadingSpinnerView()
                PulsingStatusDot(color: .green, isSyncing: true)
                QuestionBlockButton(isSyncing: true, action: {})
            }
            // The public accessibility value is read-only; this overrides it
            // for the test without changing the Mac's accessibility settings.
            .environment(\._accessibilityReduceMotion, true)
            .frame(width: 380)
        )
        window.contentView = hosting
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))

        hosting.layoutCount = 0
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        #expect(hosting.layoutCount == 0)
    }
}
