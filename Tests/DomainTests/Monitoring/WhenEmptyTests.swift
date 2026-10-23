import Foundation
import Testing
@testable import Domain

/// *Rest when empty*'s one transition: where a product is after a refresh
/// that read its status (docs/features/monitoring/rest-when-empty/design.md §2).
@Suite
struct WhenEmptyTests {
    private let noon = Date(timeIntervalSince1970: 1_761_220_000)
    private let later = Date(timeIntervalSince1970: 1_761_230_000)

    @Test
    func `should rest a watched product from the moment it is seen empty`() {
        #expect(WhenEmpty.watching.after(.depleted, now: noon) == .resting(since: noon))
    }

    @Test(arguments: [QuotaStatus.healthy, .warning, .critical])
    func `should keep watching a product that has room`(status: QuotaStatus) {
        #expect(WhenEmpty.watching.after(status, now: noon) == .watching)
    }

    @Test
    func `should keep resting since the first moment while it stays empty`() {
        #expect(WhenEmpty.resting(since: noon).after(.depleted, now: later) == .resting(since: noon))
    }

    @Test
    func `should stop resting at the first refresh that shows room`() {
        #expect(WhenEmpty.resting(since: noon).after(.critical, now: later) == .watching)
    }

    @Test(arguments: [WhenEmpty.watching, .resting(since: Date(timeIntervalSince1970: 1_761_220_000)), .shownAnyway])
    func `should change nothing when a refresh saw nothing`(state: WhenEmpty) {
        // A failed fetch, or a login not set up, is neither empty nor room.
        #expect(state.after(nil, now: later) == state)
    }

    @Test
    func `should not rest a product shown anyway while it stays empty`() {
        #expect(WhenEmpty.shownAnyway.after(.depleted, now: later) == .shownAnyway)
    }

    @Test
    func `should watch a product shown anyway again once it has had room`() {
        #expect(WhenEmpty.shownAnyway.after(.healthy, now: later) == .watching)
    }

    @Test
    func `should say it rests and since when only while resting`() {
        #expect(WhenEmpty.resting(since: noon).isResting)
        #expect(WhenEmpty.resting(since: noon).restingSince == noon)
        #expect(!WhenEmpty.watching.isResting)
        #expect(WhenEmpty.shownAnyway.restingSince == nil)
    }
}
