import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

/// `ObservationRenderSync` keeps an imperative render sink in sync with
/// `@Observable` domain state, replacing SwiftUI's menu-bar label invalidation,
/// which can permanently stop after system sleep (issue #192): the dropdown
/// keeps working while the label and its attached tasks go dead. These tests
/// verify the sync re-renders on state changes without any SwiftUI hosting.
@Suite
@MainActor
struct ObservationRenderSyncTests {
    /// Minimal observable state stand-in for QuotaMonitor/AppSettings reads.
    @Observable
    @MainActor
    final class Source {
        var value = "initial"
    }

    /// Records every value pushed to the render sink.
    @MainActor
    final class RenderRecorder {
        private(set) var rendered: [String] = []
        func record(_ value: String) { rendered.append(value) }
    }

    /// Counts how many times the sync re-read its observed state.
    @MainActor
    final class ReadCounter {
        private(set) var count = 0
        func read(_ source: Source) -> String {
            count += 1
            return source.value
        }
    }

    /// Yields the main actor enough turns for every queued re-arm hop to run.
    private func drainMainActor() async {
        for _ in 0..<100 { await Task.yield() }
    }

    /// Yields the main actor until `condition` holds or ~2s elapse, so the
    /// re-armed observation's main-actor hop gets a chance to run without
    /// real-time sleeps.
    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition() && ContinuousClock.now < deadline {
            await Task.yield()
        }
    }

    @Test
    func `renders the current value immediately on start`() {
        // Given
        let source = Source()
        let recorder = RenderRecorder()
        let sync = ObservationRenderSync(
            read: { source.value },
            render: { recorder.record($0) }
        )

        // When
        sync.start()

        // Then
        #expect(recorder.rendered == ["initial"])
    }

    @Test
    func `re-renders when observed state changes, without any SwiftUI hosting`() async {
        // Given
        let source = Source()
        let recorder = RenderRecorder()
        let sync = ObservationRenderSync(
            read: { source.value },
            render: { recorder.record($0) }
        )
        sync.start()

        // When
        source.value = "updated"
        await waitUntil { recorder.rendered.count >= 2 }

        // Then
        #expect(recorder.rendered == ["initial", "updated"])
    }

    @Test
    func `keeps tracking across multiple consecutive changes`() async {
        // Given
        let source = Source()
        let recorder = RenderRecorder()
        let sync = ObservationRenderSync(
            read: { source.value },
            render: { recorder.record($0) }
        )
        sync.start()

        // When — each change must re-arm observation for the next one
        source.value = "second"
        await waitUntil { recorder.rendered.count >= 2 }
        source.value = "third"
        await waitUntil { recorder.rendered.count >= 3 }

        // Then
        #expect(recorder.rendered == ["initial", "second", "third"])
    }

    @Test
    func `does not re-render when the read value is unchanged`() async {
        // Given — read collapses state to a constant, so writes are invisible
        let source = Source()
        let recorder = RenderRecorder()
        let sync = ObservationRenderSync(
            read: { _ = source.value; return "constant" },
            render: { recorder.record($0) }
        )
        sync.start()

        // When
        source.value = "changed underneath"
        await waitUntil { recorder.rendered.count >= 2 }

        // Then — still only the initial render
        #expect(recorder.rendered == ["constant"])
    }

    @Test
    func `stop ends rendering even if observed state keeps changing`() async {
        // Given
        let source = Source()
        let recorder = RenderRecorder()
        let sync = ObservationRenderSync(
            read: { source.value },
            render: { recorder.record($0) }
        )
        sync.start()

        // When
        sync.stop()
        source.value = "after stop"
        await waitUntil { recorder.rendered.count >= 2 }

        // Then
        #expect(recorder.rendered == ["initial"])
    }

    @Test
    func `renderNow forces a redraw of the current value`() {
        // Given — e.g. after system wake, the status item may need repainting
        let source = Source()
        let recorder = RenderRecorder()
        let sync = ObservationRenderSync(
            read: { source.value },
            render: { recorder.record($0) }
        )
        sync.start()

        // When
        sync.renderNow()

        // Then
        #expect(recorder.rendered == ["initial", "initial"])
    }

    @Test
    func `renderNow does not stack observation registrations`() async {
        // Given — the menu bar calls renderNow on every appearance change,
        // which on macOS 26 fires whenever the wallpaper behind the bar
        // changes brightness. Each call used to arm another registration
        // that was never released, growing memory without bound (#313).
        let source = Source()
        let reads = ReadCounter()
        let sync = ObservationRenderSync(
            read: { reads.read(source) },
            render: { _ in }
        )
        sync.start()
        sync.renderNow()
        sync.renderNow()
        sync.renderNow()

        // When — two genuine state changes
        let beforeFirst = reads.count
        source.value = "first"
        await waitUntil { reads.count > beforeFirst }
        await drainMainActor()
        let beforeSecond = reads.count
        source.value = "second"
        await waitUntil { reads.count > beforeSecond }
        await drainMainActor()

        // Then — a single armed registration: one re-read per change
        #expect(beforeSecond - beforeFirst == 1)
        #expect(reads.count - beforeSecond == 1)
    }

    @Test
    func `restarting does not leave a second registration armed`() async {
        // Given — stop leaves the in-flight registration armed; a start
        // before it fires must not end up with two live re-arm chains.
        let source = Source()
        let reads = ReadCounter()
        let sync = ObservationRenderSync(
            read: { reads.read(source) },
            render: { _ in }
        )
        sync.start()
        sync.stop()
        sync.start()

        // When
        source.value = "first"
        await waitUntil { reads.count > 2 }
        await drainMainActor()
        let beforeSecond = reads.count
        source.value = "second"
        await waitUntil { reads.count > beforeSecond }
        await drainMainActor()

        // Then
        #expect(reads.count - beforeSecond == 1)
    }

    // MARK: - refreshNow (self-driven ticks)

    @Test
    func `refreshNow renders when the value changed`() {
        // Given — the menu bar's countdown tick re-reads the wall clock
        let source = Source()
        let recorder = RenderRecorder()
        let sync = ObservationRenderSync(
            read: { source.value },
            render: { recorder.record($0) }
        )
        sync.start()

        // When
        source.value = "ticked"
        sync.refreshNow()

        // Then
        #expect(recorder.rendered == ["initial", "ticked"])
    }

    @Test
    func `refreshNow does not render when the value is unchanged`() {
        // Given — a colon-less menu bar label ("2d") must not repaint on every
        // tick just because the clock advanced.
        let source = Source()
        let recorder = RenderRecorder()
        let sync = ObservationRenderSync(
            read: { source.value },
            render: { recorder.record($0) }
        )
        sync.start()

        // When — many ticks with nothing changing
        sync.refreshNow()
        sync.refreshNow()
        sync.refreshNow()

        // Then — unlike renderNow, no forced repaints
        #expect(recorder.rendered == ["initial"])
    }

    @Test
    func `refreshNow leaves observation armed so later state changes still render`() async {
        // Given — refreshNow deliberately skips re-arming observation, so a
        // ticking caller cannot accumulate one registration per tick. The
        // registration from the last real sync must survive that.
        let source = Source()
        let recorder = RenderRecorder()
        let sync = ObservationRenderSync(
            read: { source.value },
            render: { recorder.record($0) }
        )
        sync.start()

        // When — ticks happen, then genuine observed state changes
        sync.refreshNow()
        sync.refreshNow()
        source.value = "observed change"
        await waitUntil { recorder.rendered.count >= 2 }

        // Then — the change still reached the sink
        #expect(recorder.rendered == ["initial", "observed change"])
    }

    @Test
    func `refreshNow does nothing before start`() {
        // Given
        let source = Source()
        let recorder = RenderRecorder()
        let sync = ObservationRenderSync(
            read: { source.value },
            render: { recorder.record($0) }
        )

        // When
        sync.refreshNow()

        // Then
        #expect(recorder.rendered.isEmpty)
    }

    @Test
    func `refreshNow does nothing after stop`() {
        // Given — the tick timer can outlive a stop by one fire
        let source = Source()
        let recorder = RenderRecorder()
        let sync = ObservationRenderSync(
            read: { source.value },
            render: { recorder.record($0) }
        )
        sync.start()
        sync.stop()

        // When
        source.value = "after stop"
        sync.refreshNow()

        // Then
        #expect(recorder.rendered == ["initial"])
    }

    @Test
    func `menu bar label content stays in sync with provider refreshes`() async {
        // Given — the real domain chain: provider snapshot → monitor → label
        let settings = MockProviderSettingsRepository()
        given(settings).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(settings).isEnabled(forProvider: .any).willReturn(true)
        given(settings).setEnabled(.any, forProvider: .any).willReturn()

        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(UsageSnapshot(
            providerId: "claude",
            quotas: [UsageQuota(percentRemaining: 64, quotaType: .session, providerId: "claude")],
            capturedAt: Date()
        ))
        let provider = ClaudeProvider(probe: probe, settingsRepository: settings)
        let monitor = QuotaMonitor(
            providers: AIProviders(providers: [provider]),
            clock: NoOpClock()
        )

        let recorder = RenderRecorder()
        let sync = ObservationRenderSync(
            read: {
                monitor.menuBarLabel(
                    providerId: "claude",
                    primaryQuotaKey: "session",
                    showPercentage: true,
                    showDuration: false,
                    mode: .remaining
                )?.text ?? "no label"
            },
            render: { recorder.record($0) }
        )
        sync.start()
        #expect(recorder.rendered == ["no label"])

        // When — a refresh replaces the provider snapshot
        await monitor.refresh(providerId: "claude")
        await waitUntil { recorder.rendered.count >= 2 }

        // Then — the sink saw the new label without any view re-evaluation
        #expect(recorder.rendered == ["no label", "64%"])
    }

    private struct NoOpClock: Clock {
        func sleep(for duration: Duration) async throws {}
        func sleep(nanoseconds: UInt64) async throws {}
    }
}
