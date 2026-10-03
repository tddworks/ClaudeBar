import Testing
import Foundation
import SwiftUI
import Domain
@testable import ClaudeBar

/// The popover's text scale is the whole feature: every popover font goes
/// through `popoverFont`, so these assertions are what make the secondary text
/// (7–10pt labels, countdowns and comparison lines) readable again.
@Suite
struct PopoverTextScaleTests {

    /// Point sizes are compared with a tolerance: `8 * 1.2` is not exactly
    /// 9.6 in binary floating point, and the policy is about proportions.
    private func isClose(_ actual: CGFloat, _ expected: CGFloat) -> Bool {
        abs(actual - expected) < 0.001
    }

    // MARK: - Scale Factors

    @Test
    func `default renders today's sizes unchanged`() {
        // Medium is today's design, so the popover must not move for anyone
        // who has not chosen a size.
        #expect(PopoverTextSize.medium.textScale == 1.0)
        #expect(isClose(PopoverTextSize.medium.scaled(8), 8))
        #expect(isClose(PopoverTextSize.medium.scaled(26), 26))
    }

    @Test
    func `every size scales monotonically`() {
        let scales = PopoverTextSize.allCases.map(\.textScale)
        #expect(zip(scales, scales.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test
    func `extra large lifts the smallest popover text above 9 points`() {
        // The complaint (#364): the 7pt clock glyph and 8pt SESSION / WEEKLY
        // labels are unreadable on a hi-DPI display.
        #expect(isClose(PopoverTextSize.extraLarge.scaled(7), 9.8))
        #expect(isClose(PopoverTextSize.extraLarge.scaled(8), 11.2))
    }

    @Test
    func `large lifts the smallest popover text too`() {
        #expect(PopoverTextSize.large.scaled(7) > PopoverTextSize.medium.scaled(7))
        #expect(PopoverTextSize.large.scaled(8) > PopoverTextSize.medium.scaled(8))
    }

    @Test
    func `no size renders text smaller than today`() {
        // #364 asked for more readable text, so every offered size is at least
        // the current design: there is no step that shrinks the 7pt glyphs and
        // 8pt card labels.
        #expect(PopoverTextSize.allCases.allSatisfy { $0.textScale >= 1.0 })
        #expect(PopoverTextSize.allCases.allSatisfy { $0.scaled(7) >= 7 })
    }

    @Test
    func `scaling is proportional, not clamped`() {
        // A number twice as big must render twice as big, or the popover stops
        // looking like one design at the larger sizes.
        #expect(isClose(
            PopoverTextSize.extraLarge.scaled(16),
            2 * PopoverTextSize.extraLarge.scaled(8)
        ))
    }

    // MARK: - The Width Follows The Text

    @Test
    func `each size widens the popover in step with its text`() {
        // Text and width move together so nothing that fits today truncates at
        // a larger size.
        #expect(PopoverTextSize.medium.popoverWidth == 400)
        #expect(PopoverTextSize.large.popoverWidth == 480)
        #expect(PopoverTextSize.extraLarge.popoverWidth == 560)
    }

    @Test
    func `every size above Default is wider than the old fixed 400 points`() {
        // The popover used to hardcode `.frame(width: 400)`. If the width ever
        // stops following the policy again, the two larger sizes draw their
        // 1.2x / 1.4x text inside a window sized for 1.0x and everything
        // truncates.
        #expect(PopoverContentWidth.base == 400)
        #expect(PopoverTextSize.large.popoverWidth != PopoverContentWidth.base)
        #expect(PopoverTextSize.extraLarge.popoverWidth != PopoverContentWidth.base)
    }

    // MARK: - The Environment Value

    @Test
    func `views read the default size until the popover injects a choice`() {
        // A view rendered outside the popover (a preview, a snapshot) must not
        // need the environment set up to draw.
        #expect(EnvironmentValues().popoverTextSize == .default)
        var injected = EnvironmentValues()
        injected.popoverTextSize = .large
        #expect(injected.popoverTextSize == .large)
    }
}