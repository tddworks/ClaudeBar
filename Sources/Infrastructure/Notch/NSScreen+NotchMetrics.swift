import AppKit
import Domain

public extension NSScreen {
    /// Measures this display's notch region.
    ///
    /// Every rule lives in `NotchMetrics.measure`; this is only the AppKit read.
    /// `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` are the usable menu bar
    /// areas either side of the cutout — subtracting them from the full width is
    /// the only way to learn how wide the notch is, since macOS exposes no API
    /// for it.
    var notchMetrics: NotchMetrics {
        NotchMetrics.measure(
            screenWidth: frame.width,
            safeAreaTop: safeAreaInsets.top,
            auxiliaryTopLeftWidth: auxiliaryTopLeftArea?.width,
            auxiliaryTopRightWidth: auxiliaryTopRightArea?.width,
            menuBarHeight: frame.maxY - visibleFrame.maxY
        )
    }

    /// The display ClaudeBar draws its notch on: the one with a real cutout if
    /// there is one, otherwise the main display.
    static var preferredNotchScreen: NSScreen? {
        screens.first { $0.safeAreaInsets.top > 0 } ?? main ?? screens.first
    }
}
