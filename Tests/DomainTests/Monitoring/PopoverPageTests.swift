import Foundation
import Testing
@testable import Domain

/// Which page the popover shows, and where an open lands.
@Suite
struct PopoverPageTests {
    @Test
    func `should fall back to the provider when All is no longer offered`() {
        #expect(PopoverPage.all.shown(allOffered: false, leaderboardOn: true) == .provider)
        #expect(PopoverPage.all.shown(allOffered: true, leaderboardOn: false) == .all)
    }

    @Test
    func `should fall back to the provider when the Leaderboard is turned off`() {
        #expect(PopoverPage.leaderboard.shown(allOffered: true, leaderboardOn: false) == .provider)
    }

    @Test
    func `should open on All every time when the person chose All`() {
        #expect(PopoverOpensOn.all.page(onOpening: .provider) == .all)
        #expect(PopoverOpensOn.all.page(onOpening: .leaderboard) == .all)
    }

    @Test
    func `should open where the person left it by default`() {
        #expect(PopoverOpensOn.whereILeftIt.page(onOpening: .leaderboard) == .leaderboard)
        #expect(PopoverOpensOn.whereILeftIt.page(onOpening: .provider) == .provider)
    }
}
