import AppKit
import SwiftUI

/// Makes the popover's window key whenever the popover comes on screen.
///
/// Clicking the status item hands the popover key status, so Escape and the
/// ⌘ shortcuts work. Opening it programmatically (`claudebar://open` from
/// Alfred or a Touch Bar tap) only orders the window in: the app activates,
/// but no window is key, and every key press goes nowhere. Asking for key
/// status once the window exists covers both paths; when the window already
/// is key the call is a no-op.
struct PopoverKeyWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> KeyWindowClaimingView {
        KeyWindowClaimingView()
    }

    func updateNSView(_ nsView: KeyWindowClaimingView, context: Context) {}
}

final class KeyWindowClaimingView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        // The window is still being ordered in at this point; the URL handler
        // activates the app right after. Claim key status on the next turn so
        // the activation doesn't undo it.
        DispatchQueue.main.async { [weak window] in
            guard let window, !window.isKeyWindow else { return }
            window.makeKey()
        }
    }
}
