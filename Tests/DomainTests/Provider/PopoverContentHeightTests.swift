import Testing
import Foundation
@testable import Domain

@Suite
struct PopoverContentHeightTests {

    // MARK: - Fit Invariant

    @Test(arguments: [560.0, 735.0, 800.0, 982.0, 1200.0])
    func `single-provider cap plus chrome never exceeds the screen`(screenHeight: Double) {
        let cap = PopoverContentHeight.maxHeight(
            visibleScreenHeight: screenHeight,
            overviewMode: false
        )
        #expect(cap + PopoverContentHeight.chrome <= screenHeight)
    }

    @Test(arguments: [560.0, 735.0, 800.0, 982.0, 1200.0])
    func `overview cap plus chrome never exceeds the screen`(screenHeight: Double) {
        let cap = PopoverContentHeight.maxHeight(
            visibleScreenHeight: screenHeight,
            overviewMode: true
        )
        #expect(cap + PopoverContentHeight.chrome <= screenHeight)
    }

    // MARK: - Mode Behavior

    @Test
    func `single-provider cap uses the full remainder on a normal display`() {
        // 14" MacBook Pro visible frame ≈ 982pt → the Oh My Pi card set
        // gets the whole remainder instead of an artificial ceiling.
        let cap = PopoverContentHeight.maxHeight(visibleScreenHeight: 982, overviewMode: false)
        #expect(cap == 982 - PopoverContentHeight.chrome)
    }

    @Test
    func `overview keeps its 500pt ceiling on a normal display`() {
        let cap = PopoverContentHeight.maxHeight(visibleScreenHeight: 982, overviewMode: true)
        #expect(cap == 500)
    }

    @Test
    func `overview shrinks below its ceiling on short displays`() {
        // 735pt visible frame → 500 + chrome would overflow; the remainder wins.
        let cap = PopoverContentHeight.maxHeight(visibleScreenHeight: 735, overviewMode: true)
        #expect(cap == 735 - PopoverContentHeight.chrome)
    }

    // MARK: - Degenerate Displays

    @Test
    func `degenerate displays get the usable floor instead of collapsing`() {
        let cap = PopoverContentHeight.maxHeight(visibleScreenHeight: 400, overviewMode: false)
        #expect(cap == PopoverContentHeight.usableFloor)
    }
}
