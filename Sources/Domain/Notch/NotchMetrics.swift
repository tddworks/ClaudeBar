import CoreGraphics
import Foundation

/// The size and nature of the notch region on one display.
///
/// macOS exposes no notch API. The measurement is inferred from the *auxiliary
/// menu bar areas* either side of the cutout, and whether a display has a notch
/// at all is inferred from its top safe-area inset. Both rules are subtle
/// enough to be worth isolating from AppKit so they can be tested directly.
public struct NotchMetrics: Sendable, Equatable {
    /// Width of a virtual notch, and the fallback whenever the real one cannot
    /// be measured. Close to the physical notch on a 14"/16" MacBook Pro.
    public static let defaultWidth: CGFloat = 185

    /// Fallback height for displays that report no menu bar — an auto-hidden
    /// menu bar measures as zero.
    public static let defaultHeight: CGFloat = 32

    /// Drawn slightly wider than measured so the notch overlays the physical
    /// cutout's edges instead of leaving a hairline seam beside them.
    private static let seamOverlap: CGFloat = 4

    /// Below this, a measurement is not a notch — it is a transient screen
    /// configuration, and drawing it would collapse the notch to a sliver.
    private static let plausibleMinimumWidth: CGFloat = 100

    /// The notch at rest, before any activity widens it.
    public let closedSize: CGSize

    /// Whether this display has a real cutout. False means ClaudeBar draws a
    /// virtual notch at top centre — roughly half of installs.
    public let isPhysicalNotch: Bool

    public init(closedSize: CGSize, isPhysicalNotch: Bool) {
        self.closedSize = closedSize
        self.isPhysicalNotch = isPhysicalNotch
    }

    /// Derives the metrics from one display's raw measurements.
    ///
    /// - Parameters:
    ///   - screenWidth: The display's full width in points.
    ///   - safeAreaTop: The top safe-area inset. Greater than zero means a notch.
    ///   - auxiliaryTopLeftWidth: Usable menu bar width left of the cutout, if any.
    ///   - auxiliaryTopRightWidth: Usable menu bar width right of the cutout, if any.
    ///   - menuBarHeight: The menu bar's height, used for displays with no notch.
    public static func measure(
        screenWidth: CGFloat,
        safeAreaTop: CGFloat,
        auxiliaryTopLeftWidth: CGFloat?,
        auxiliaryTopRightWidth: CGFloat?,
        menuBarHeight: CGFloat
    ) -> NotchMetrics {
        let isPhysicalNotch = safeAreaTop > 0

        return NotchMetrics(
            closedSize: CGSize(
                width: width(
                    screenWidth: screenWidth,
                    auxiliaryTopLeftWidth: auxiliaryTopLeftWidth,
                    auxiliaryTopRightWidth: auxiliaryTopRightWidth
                ),
                height: height(
                    isPhysicalNotch: isPhysicalNotch,
                    safeAreaTop: safeAreaTop,
                    menuBarHeight: menuBarHeight
                )
            ),
            isPhysicalNotch: isPhysicalNotch
        )
    }

    // MARK: - Private

    private static func width(
        screenWidth: CGFloat,
        auxiliaryTopLeftWidth: CGFloat?,
        auxiliaryTopRightWidth: CGFloat?
    ) -> CGFloat {
        guard let left = auxiliaryTopLeftWidth, let right = auxiliaryTopRightWidth else {
            return defaultWidth
        }
        let measured = screenWidth - left - right + seamOverlap
        return measured >= plausibleMinimumWidth ? measured : defaultWidth
    }

    private static func height(
        isPhysicalNotch: Bool,
        safeAreaTop: CGFloat,
        menuBarHeight: CGFloat
    ) -> CGFloat {
        if isPhysicalNotch { return safeAreaTop }
        return menuBarHeight > 0 ? menuBarHeight : defaultHeight
    }
}
