import AppKit
import SwiftUI
import Domain
import Infrastructure

/// Owns the notch window: where it sits, which display it is on, and which part
/// of it accepts the mouse.
///
/// Everything about *what* to show is decided upstream by
/// `NotchActivityResolver`; this only puts pixels on a screen.
@MainActor
final class NotchWindowController {
    /// A canvas comfortably larger than any notch state, so the window never
    /// has to resize while the notch animates inside it.
    private static let canvasSize = CGSize(width: 900, height: 420)

    /// Forgiveness around the drawn notch, so hover does not drop out on the
    /// exact boundary.
    private static let hoverPadding: CGFloat = 6

    private let state = NotchViewState()
    private var window: NotchWindow?
    private var hostingView: NotchHostingView<AnyView>?
    private var screenObserver: NSObjectProtocol?
    private var contentSizeSync: ObservationRenderSync<CGSize>?
    private var mouseMonitor: Any?

    /// The live notch region in window coordinates. Drives both which clicks
    /// the window accepts and whether the pointer counts as hovering.
    private var interactiveRect: CGRect = .zero

    /// Last known answer to "is the pointer over the notch". Kept so the
    /// tracking callback can bail out without touching observable state.
    private var isPointerOverNotch = false

    private(set) var isRunning = false


    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true

        let window = NotchWindow(contentRect: NSRect(origin: .zero, size: Self.canvasSize))
        let hostingView = NotchHostingView(
            rootView: AnyView(NotchRootView(state: state))
        )
        window.contentView = hostingView

        self.window = window
        self.hostingView = hostingView

        observeScreenChanges()
        observeContentSize()
        observeMouse()
        reposition()

        AppLog.ui.info("Notch window started")
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        contentSizeSync?.stop()
        contentSizeSync = nil

        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }

        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }

        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        hostingView = nil

        AppLog.ui.info("Notch window stopped")
    }

    // MARK: - Content

    /// Hands the notch everything it draws, in one go.
    ///
    /// With nothing to say the window is ordered out rather than left on screen
    /// drawing a closed notch. On a display with a real cutout that shape is
    /// invisible, but on the virtual notch every other display gets it is a
    /// black box sitting in the menu bar that cannot be opened.
    func update(content: NotchContent) {
        guard isRunning else { return }
        state.content = content

        guard content.activity != nil else {
            if state.isExpanded { state.isExpanded = false }
            hide()
            return
        }

        // Re-pick the display each time the notch has something new to say, so
        // it appears where the user is rather than wherever they were at launch.
        reposition()
        window?.orderFrontRegardless()
    }

    private func hide() {
        window?.orderOut(nil)
        isPointerOverNotch = false
        window?.ignoresMouseEvents = true
    }

    /// Wires the panel's buttons to the app.
    func setActions(refresh: @escaping () -> Void, snooze: @escaping () -> Void) {
        state.refresh = refresh
        state.snooze = snooze
    }

    // MARK: - Placement

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reposition()
            }
        }
    }

    /// Re-measures the display and re-anchors the canvas to the top of it.
    private func reposition() {
        guard let window, let screen = NSScreen.preferredNotchScreen else { return }

        state.metrics = screen.notchMetrics

        let frame = NSRect(
            x: screen.frame.midX - Self.canvasSize.width / 2,
            y: screen.frame.maxY - Self.canvasSize.height,
            width: Self.canvasSize.width,
            height: Self.canvasSize.height
        )
        window.setFrame(frame, display: true, animate: false)
        updateInteractiveRect()
    }

    /// Tracks the size SwiftUI actually laid the notch out at, and turns it into
    /// the window-coordinate rect that `NotchHostingView` hit-tests against.
    private func observeContentSize() {
        let sync = ObservationRenderSync<CGSize>(
            read: { [state] in state.contentSize },
            render: { [weak self] _ in self?.updateInteractiveRect() }
        )
        contentSizeSync = sync
        sync.start()
    }

    /// Tracks the pointer so the window can get out of the way.
    ///
    /// `hitTest` returning nil is *not* click-through: the window still
    /// swallows the event rather than passing it to whatever is behind. The
    /// only mechanism that genuinely lets a click reach the menu bar below is
    /// `ignoresMouseEvents`, so the window ignores the mouse by default and
    /// only accepts it while the pointer is actually over the notch.
    ///
    /// A global monitor for `.mouseMoved` needs no Accessibility permission —
    /// unlike keyboard monitors — so this stays sandbox- and MAS-safe.
    private func observeMouse() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateMouseTracking()
            }
        }
    }

    /// Called for every mouse-moved event anywhere on screen, so it must do
    /// nothing at all in the common case.
    ///
    /// `@Observable` has no equality check: assigning the same value still
    /// fires observers, so writing `isExpanded` unconditionally here would
    /// invalidate the notch's SwiftUI tree on every pointer movement across the
    /// entire display.
    private func updateMouseTracking() {
        guard let window else { return }

        let mouseInWindow = CGPoint(
            x: NSEvent.mouseLocation.x - window.frame.origin.x,
            y: NSEvent.mouseLocation.y - window.frame.origin.y
        )
        let isOverNotch = interactiveRect.contains(mouseInWindow)
        let shouldExpand = isOverNotch && state.activity != nil

        guard isOverNotch != isPointerOverNotch || shouldExpand != state.isExpanded else { return }

        isPointerOverNotch = isOverNotch
        window.ignoresMouseEvents = !isOverNotch
        state.isExpanded = shouldExpand
    }

    private func updateInteractiveRect() {
        guard let hostingView, let window else { return }

        let size = state.contentSize
        guard size.width > 0, size.height > 0 else {
            interactiveRect = .zero
            hostingView.interactiveRect = .zero
            window.ignoresMouseEvents = true
            isPointerOverNotch = false
            return
        }

        // The content is centred horizontally and pinned to the top of the
        // canvas. Window coordinates are y-up, so the top edge is the canvas
        // height.
        let rect = CGRect(
            x: (Self.canvasSize.width - size.width) / 2,
            y: Self.canvasSize.height - size.height,
            width: size.width,
            height: size.height
        )
        interactiveRect = rect.insetBy(dx: -Self.hoverPadding, dy: -Self.hoverPadding)
        hostingView.interactiveRect = interactiveRect
        updateMouseTracking()
    }
}
