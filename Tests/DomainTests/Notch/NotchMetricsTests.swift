import Testing
import Foundation
@testable import Domain

@Suite
struct NotchMetricsTests {
    // A 14" MacBook Pro at its default scaled resolution: 1512pt wide, a 32pt
    // menu bar, and ~663.5pt of usable menu bar either side of the notch.
    private let builtInDisplayWidth: CGFloat = 1512
    private let builtInAuxiliaryWidth: CGFloat = 663.5

    @Test
    func `a notched display measures the notch from the auxiliary areas either side`() {
        let metrics = NotchMetrics.measure(
            screenWidth: builtInDisplayWidth,
            safeAreaTop: 32,
            auxiliaryTopLeftWidth: builtInAuxiliaryWidth,
            auxiliaryTopRightWidth: builtInAuxiliaryWidth,
            menuBarHeight: 32
        )

        // 1512 - 663.5 - 663.5 = 185, plus the 4pt overlap that hides the seam.
        #expect(metrics.closedSize.width == 189)
        #expect(metrics.isPhysicalNotch)
    }

    @Test
    func `a notched display takes its height from the safe area inset`() {
        let metrics = NotchMetrics.measure(
            screenWidth: builtInDisplayWidth,
            safeAreaTop: 38,
            auxiliaryTopLeftWidth: builtInAuxiliaryWidth,
            auxiliaryTopRightWidth: builtInAuxiliaryWidth,
            menuBarHeight: 24
        )

        #expect(metrics.closedSize.height == 38)
    }

    @Test
    func `a display without a notch gets a virtual pill of the default width`() {
        let metrics = NotchMetrics.measure(
            screenWidth: 2560,
            safeAreaTop: 0,
            auxiliaryTopLeftWidth: nil,
            auxiliaryTopRightWidth: nil,
            menuBarHeight: 24
        )

        #expect(metrics.closedSize.width == NotchMetrics.defaultWidth)
        #expect(metrics.isPhysicalNotch == false)
    }

    @Test
    func `a display without a notch takes its height from the menu bar`() {
        let metrics = NotchMetrics.measure(
            screenWidth: 2560,
            safeAreaTop: 0,
            auxiliaryTopLeftWidth: nil,
            auxiliaryTopRightWidth: nil,
            menuBarHeight: 24
        )

        #expect(metrics.closedSize.height == 24)
    }

    @Test
    func `an auto-hidden menu bar falls back to the default height`() {
        // visibleFrame reaches the top of the screen when the menu bar hides,
        // which measures as a zero-height menu bar.
        let metrics = NotchMetrics.measure(
            screenWidth: 2560,
            safeAreaTop: 0,
            auxiliaryTopLeftWidth: nil,
            auxiliaryTopRightWidth: nil,
            menuBarHeight: 0
        )

        #expect(metrics.closedSize.height == NotchMetrics.defaultHeight)
    }

    @Test
    func `a notched display missing its auxiliary areas falls back to the default width`() {
        let metrics = NotchMetrics.measure(
            screenWidth: builtInDisplayWidth,
            safeAreaTop: 32,
            auxiliaryTopLeftWidth: nil,
            auxiliaryTopRightWidth: builtInAuxiliaryWidth,
            menuBarHeight: 32
        )

        #expect(metrics.closedSize.width == NotchMetrics.defaultWidth)
        #expect(metrics.closedSize.height == 32)
    }

    @Test
    func `an implausibly narrow measurement falls back rather than collapsing the notch`() {
        // Guards against a transient screen configuration reporting auxiliary
        // areas that consume the whole width.
        let metrics = NotchMetrics.measure(
            screenWidth: builtInDisplayWidth,
            safeAreaTop: 32,
            auxiliaryTopLeftWidth: 756,
            auxiliaryTopRightWidth: 756,
            menuBarHeight: 32
        )

        #expect(metrics.closedSize.width == NotchMetrics.defaultWidth)
    }
}
