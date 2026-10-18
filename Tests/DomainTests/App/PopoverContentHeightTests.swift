import Testing
import Foundation
@testable import Domain

@Suite
struct PopoverContentHeightTests {

    // MARK: - Fit Invariant

    @Test(arguments: [560.0, 735.0, 800.0, 982.0, 1200.0])
    func `should never make the popover taller than the screen for one provider`(screenHeight: Double) {
        let cap = PopoverContentHeight.maxHeight(
            visibleScreenHeight: screenHeight,
            overviewMode: false
        )
        #expect(cap + PopoverContentHeight.chrome <= screenHeight)
    }

    @Test(arguments: [560.0, 735.0, 800.0, 982.0, 1200.0])
    func `should never make the popover taller than the screen in the overview`(screenHeight: Double) {
        let cap = PopoverContentHeight.maxHeight(
            visibleScreenHeight: screenHeight,
            overviewMode: true
        )
        #expect(cap + PopoverContentHeight.chrome <= screenHeight)
    }

    // MARK: - Mode Behavior

    @Test
    func `should give one provider's cards all the screen height left on a normal display`() {
        // 14" MacBook Pro visible frame ≈ 982pt → the Oh My Pi card set
        // gets the whole remainder instead of an artificial ceiling.
        let cap = PopoverContentHeight.maxHeight(visibleScreenHeight: 982, overviewMode: false)
        #expect(cap == 982 - PopoverContentHeight.chrome)
    }

    @Test
    func `should keep the overview at most 500pt tall on a normal display`() {
        let cap = PopoverContentHeight.maxHeight(visibleScreenHeight: 982, overviewMode: true)
        #expect(cap == 500)
    }

    @Test
    func `should shrink the overview below 500pt to fit a short display`() {
        // 735pt visible frame → 500 + chrome would overflow; the remainder wins.
        let cap = PopoverContentHeight.maxHeight(visibleScreenHeight: 735, overviewMode: true)
        #expect(cap == 735 - PopoverContentHeight.chrome)
    }

    // MARK: - The Claude Code card

    @Test
    func `should leave room for the Claude Code card above the cards, so the action bar stays on screen`() {
        let without = PopoverContentHeight.maxHeight(visibleScreenHeight: 982, overviewMode: false)
        let with = PopoverContentHeight.maxHeight(visibleScreenHeight: 982, overviewMode: false, sessionCardHeight: 180)
        #expect(with == without - 180)
    }

    @Test
    func `should still keep the overview under its ceiling when the Claude Code card is small`() {
        let cap = PopoverContentHeight.maxHeight(visibleScreenHeight: 982, overviewMode: true, sessionCardHeight: 60)
        #expect(cap == 500)
    }

    @Test
    func `should keep the smallest usable height even when the Claude Code card is tall on a short display`() {
        let cap = PopoverContentHeight.maxHeight(visibleScreenHeight: 560, overviewMode: false, sessionCardHeight: 200)
        #expect(cap == PopoverContentHeight.usableFloor)
    }

    // MARK: - Degenerate Displays

    @Test
    func `should keep the popover at its smallest usable height rather than collapse on a tiny display`() {
        let cap = PopoverContentHeight.maxHeight(visibleScreenHeight: 400, overviewMode: false)
        #expect(cap == PopoverContentHeight.usableFloor)
    }
}
