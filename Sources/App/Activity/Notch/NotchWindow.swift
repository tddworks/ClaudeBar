import AppKit
import SwiftUI

/// The panel the notch is drawn in.
///
/// A fixed, oversized, transparent canvas anchored to the top of the screen —
/// the notch animates *inside* it rather than the window resizing, which is how
/// both boring.notch and DynamicNotch avoid visible resize jank.
///
/// `canBecomeKey` and `canBecomeMain` stay false on purpose. ClaudeBar's notch
/// has nothing to type into, and it must never pull focus from the terminal the
/// user is working in.
final class NotchWindow: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        // The canvas is far wider than the notch and sits over the menu bar.
        // It stays transparent to the mouse until the pointer is actually over
        // the notch — see NotchWindowController.updateMouseTracking.
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        // Above the menu bar. Both reference implementations converged here.
        level = .mainMenu + 3

        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary,
        ]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hosts the notch content and decides which clicks are the notch's.
///
/// The canvas is far larger than the drawn notch, and it sits directly over the
/// menu bar. Without this, the transparent remainder of the window would
/// swallow every click aimed at a menu bar item near the centre of the screen.
///
/// This view is the window's `contentView`, so `hitTest(_:)` receives points in
/// window coordinates — no conversion, and no dependence on flippedness.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    /// The live notch region, in window coordinates. Everything outside it
    /// falls through to whatever is behind the window.
    var interactiveRect: CGRect = .zero

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard interactiveRect.contains(point) else { return nil }
        return super.hitTest(point)
    }
}
