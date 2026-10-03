import Testing
import Foundation
@testable import Domain

@Suite
struct PopoverContentWidthTests {

    /// Widths are compared with a tolerance: `base * 1.2` is not exactly 480
    /// in binary floating point, and the policy is about proportions.
    private func isClose(_ actual: CGFloat, _ expected: CGFloat) -> Bool {
        abs(actual - expected) < 0.001
    }

    // MARK: - Base Width

    @Test
    func `the base width is the popover's original 400 points`() {
        // This is the literal the popover used to hardcode; the width is now
        // derived from the text size, and 400 must stay what Default renders.
        #expect(PopoverContentWidth.base == 400)
    }

    @Test
    func `scale one keeps the base width`() {
        #expect(isClose(PopoverContentWidth.width(scale: 1), 400))
    }

    // MARK: - Proportional Growth

    @Test
    func `bigger text gets a proportionally wider popover`() {
        #expect(isClose(PopoverContentWidth.width(scale: 1.2), 480))
        #expect(isClose(PopoverContentWidth.width(scale: 1.4), 560))
    }

    @Test
    func `smaller text never narrows the popover`() {
        // Narrowing the window as well would squeeze the headline numbers into
        // truncation; the smaller text alone already makes a denser popover.
        #expect(isClose(PopoverContentWidth.width(scale: 0.9), 400))
        #expect(isClose(PopoverContentWidth.width(scale: 0), 400))
    }

    @Test
    func `width never decreases as the text scale grows`() {
        // Text and width move together on purpose: a line that fits at one
        // size must still fit at the next, so nothing new truncates.
        let widths = [0.9, 1.0, 1.2, 1.4].map { PopoverContentWidth.width(scale: CGFloat($0)) }
        #expect(zip(widths, widths.dropFirst()).allSatisfy { $0 <= $1 })
    }
}