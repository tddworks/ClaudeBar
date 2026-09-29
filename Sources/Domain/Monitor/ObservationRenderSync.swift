import Foundation
import Observation

/// Keeps an imperative render sink in sync with `@Observable` domain state,
/// independent of SwiftUI view invalidation.
///
/// SwiftUI's `MenuBarExtra` label hosting can permanently stop re-evaluating
/// after system sleep: the dropdown window keeps updating while the label —
/// and any `.task` attached to it — never receives invalidations again until
/// relaunch (issue #192). This sync replaces that fragile path for the menu
/// bar: it re-arms `withObservationTracking` around a `read` closure and
/// pushes each distinct value to `render`, so whatever `render` drives (e.g.
/// an `NSStatusItem` button image) stays correct for the app's lifetime.
///
/// `read` should gather *all* state the rendering depends on — every
/// `@Observable` property it touches is tracked, and any change re-runs the
/// cycle. `render` receives only values that differ from the last one
/// rendered, so cheap no-op changes don't repaint the menu bar.
///
/// **Only `start` and a genuine `onChange` arm**, which is what holds the
/// registration count at one — and the count is load-bearing: a
/// `withObservationTracking` registration is released only when it fires, and
/// *every* armed registration fires on a write, so a second one does not merely
/// sit there, it multiplies the re-arms on the next state change. Every other
/// entry point therefore re-reads untracked.
///
/// A registration cannot be cancelled — that needs the macOS 27 token API — so
/// `stop` only advances a generation counter that stops a stranded registration
/// from re-arming when it finally fires. Restarts with no state change in
/// between leave one stranded registration each, and each retires at the next
/// write.
@MainActor
public final class ObservationRenderSync<Content: Equatable> {
    private let read: @MainActor () -> Content
    private let render: @MainActor (Content) -> Void
    private var lastRendered: Content?
    private var isStarted = false

    /// Incremented on every arm and on `stop`. A registration captures the
    /// generation it was armed with, so one stranded by an earlier
    /// start/stop cycle retires on its next fire instead of re-arming
    /// alongside the current one. It is still live until then — `stop` cannot
    /// unregister it — but it no longer counts.
    private var armGeneration = 0

    public init(
        read: @escaping @MainActor () -> Content,
        render: @escaping @MainActor (Content) -> Void
    ) {
        self.read = read
        self.render = render
    }

    /// Starts observing and renders the current value immediately.
    public func start() {
        guard !isStarted else { return }
        isStarted = true
        sync()
    }

    /// Stops observing and rendering. The in-flight tracking registration may
    /// fire one final `onChange`, which is ignored once stopped.
    public func stop() {
        isStarted = false
        armGeneration += 1
    }

    /// Re-renders the current value even if unchanged — e.g. after system
    /// wake, when the menu bar may have been repainted with stale content.
    ///
    /// Re-reads and draws, but does **not** arm a new registration: the one
    /// from the last `sync` is still armed and still catches genuine state
    /// changes, and arming here would strand the previous registration —
    /// unregistered, and re-armed again on its next fire. Since every armed
    /// registration fires on every write, a caller that forces a redraw per
    /// event (the menu bar redraws on each background-refresh tick, dropdown
    /// open/close, appearance flip and status-bar re-attach) would accumulate
    /// one live registration per event, each retaining the key-path set and
    /// closures behind its `read` — an unbounded heap climb whose per-write
    /// cost, and so CPU floor, rises with it (issue #313).
    public func renderNow() {
        guard isStarted else { return }
        let content = read()
        lastRendered = content
        render(content)
    }

    /// `renderNow` for callers that drive their own tick (the menu bar's
    /// countdown ticks twice a second) and must not pay for a forced redraw:
    /// like `renderNow` it leaves the live registration alone, but it also
    /// keeps the equality check, so a label that does not change — a `2d` with
    /// no colon to pulse — is re-read without repainting.
    public func refreshNow() {
        guard isStarted else { return }
        let content = read()
        if content != lastRendered {
            lastRendered = content
            render(content)
        }
    }

    private func sync() {
        guard isStarted else { return }
        armGeneration += 1
        let generation = armGeneration
        let content = withObservationTracking {
            read()
        } onChange: { [weak self] in
            // onChange fires on willSet; hop to the next main-actor turn so
            // the re-read below observes the *new* value, then re-arm.
            Task { @MainActor [weak self] in
                guard let self, self.isStarted, generation == self.armGeneration else { return }
                self.sync()
            }
        }
        if content != lastRendered {
            lastRendered = content
            render(content)
        }
    }
}
