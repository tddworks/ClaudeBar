import AppKit
import Infrastructure

/// Receives `claudebar://` URLs for the app's whole lifetime.
///
/// SwiftUI delivers a URL to a window scene and then to the `.onOpenURL`
/// views inside it. A `MenuBarExtra` is not a window scene, so a handler on
/// the popover's content never sees the URL. Worse, SwiftUI presents the only
/// window scene it has, the Settings window, to deliver it, which is how
/// `claudebar://open` used to open Settings. AppKit hands URLs to the
/// application delegate before any of that, so the routing lives here.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Runs each action. The app installs it once its scenes exist; actions
    /// that arrive earlier (a launch triggered by the URL itself) wait here.
    var onAction: ((URLSchemeAction) -> Void)? {
        didSet { deliverPending() }
    }

    private var pending: [URLSchemeAction] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let action = URLSchemeAction(url: url) else {
                AppLog.ui.info("Received unhandled URL: \(url.absoluteString)")
                continue
            }
            AppLog.ui.info("Received URL action: \(action.rawValue)")
            pending.append(action)
        }
        deliverPending()
    }

    private func deliverPending() {
        guard let onAction, !pending.isEmpty else { return }
        let actions = pending
        pending.removeAll()
        actions.forEach(onAction)
    }
}
