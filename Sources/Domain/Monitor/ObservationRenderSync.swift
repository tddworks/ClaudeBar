import Quotas
import DataSources
import Providers
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
    /// Identifies the one registration allowed to re-arm. A registration is
    /// only torn down when it fires, so any older one still armed must not
    /// start a second re-arm chain when it does.
    private var armedGeneration = 0

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
    ///
    /// Does not arm a new observation registration: the menu bar calls this
    /// on every background refresh and every appearance change, and each
    /// extra registration stayed armed until the next observed change, then
    /// re-armed itself — memory grew without bound (#313). The registration
    /// from the last real `sync` already catches genuine state changes.
    public func renderNow() {
        guard isStarted else { return }
        lastRendered = nil
        refreshNow()
    }

    /// Re-reads and renders *only if the value changed*, without arming a new
    /// observation registration.
    ///
    /// For callers that drive their own tick (the menu bar's countdown ticks
    /// twice a second). Only `sync` arms a `withObservationTracking`
    /// registration, and a registration is only torn down when it fires — so
    /// arming from a ticking caller would accumulate one per tick, all of them
    /// armed on the same properties, until some observed value finally changed
    /// and fired the whole backlog at once.
    ///
    /// Skipping the re-arm is safe: the registration from the last real `sync`
    /// is still armed and still catches genuine state changes. Reading the
    /// values untracked here does not consume it.
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
        armedGeneration += 1
        let generation = armedGeneration
        let content = withObservationTracking {
            read()
        } onChange: { [weak self] in
            // onChange fires on willSet; hop to the next main-actor turn so
            // the re-read below observes the *new* value, then re-arm.
            Task { @MainActor [weak self] in
                guard let self, self.armedGeneration == generation else { return }
                self.sync()
            }
        }
        if content != lastRendered {
            lastRendered = content
            render(content)
        }
    }
}
