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
@MainActor
public final class ObservationRenderSync<Content: Equatable> {
    private let read: @MainActor () -> Content
    private let render: @MainActor (Content) -> Void
    private var lastRendered: Content?
    private var isStarted = false

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
    }

    /// Re-renders the current value even if unchanged — e.g. after system
    /// wake, when the menu bar may have been repainted with stale content.
    public func renderNow() {
        guard isStarted else { return }
        lastRendered = nil
        sync()
    }

    private func sync() {
        guard isStarted else { return }
        let content = withObservationTracking {
            read()
        } onChange: { [weak self] in
            // onChange fires on willSet; hop to the next main-actor turn so
            // the re-read below observes the *new* value, then re-arm.
            Task { @MainActor [weak self] in
                self?.sync()
            }
        }
        if content != lastRendered {
            lastRendered = content
            render(content)
        }
    }
}
