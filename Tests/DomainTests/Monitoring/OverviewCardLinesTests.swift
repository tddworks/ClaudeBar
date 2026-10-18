import Foundation
import Testing
@testable import Domain

/// The *Bars* page's lines: every quota the card's login has, ordered so like
/// sits beside like across rows (docs/features/all-providers/design.md).
@MainActor
@Suite
struct OverviewCardLinesTests {
    private func quota(
        _ left: Double,
        _ type: QuotaType = .session,
        windowHours: Double? = nil
    ) -> UsageQuota {
        let window = windowHours.map { $0 * 3600 }
        return UsageQuota(
            percentRemaining: left,
            quotaType: type,
            providerId: "p",
            resetsAt: window.map { Date().addingTimeInterval($0) },
            windowDuration: window
        )
    }

    private func login(_ id: String, _ snapshot: UsageSnapshot?) -> OverviewCard.Login {
        OverviewCard.Login(id: id, name: id, snapshot: snapshot,
                           status: snapshot?.overallStatus,
                           state: .init())
    }

    private func card(_ id: String, _ logins: OverviewCard.Login...) -> OverviewCard {
        OverviewCard(id: id, name: id, logins: logins)
    }

    private func snapshot(_ quotas: UsageQuota...) -> UsageSnapshot {
        UsageSnapshot(providerId: "p", quotas: quotas, capturedAt: Date())
    }

    @Test
    func `should draw every quota the card reads, not just the tightest two`() {
        let card = card("claude", login("claude", snapshot(
            quota(9, .session, windowHours: 5),
            quota(35, .weekly, windowHours: 24 * 7),
            quota(34, .modelSpecific("opus"), windowHours: 24 * 7),
            quota(52, .modelSpecific("sonnet"), windowHours: 24 * 7)
        )))

        #expect(card.lines.count == 4)
    }

    @Test
    func `should order lines by their stated window, shortest first`() {
        let card = card("claude", login("claude", snapshot(
            quota(35, .weekly, windowHours: 24 * 7),
            quota(52, .modelSpecific("sonnet"), windowHours: 24 * 7),
            quota(9, .session, windowHours: 5)
        )))

        #expect(card.lines.map(\.quotaType) == [.session, .weekly, .modelSpecific("sonnet")])
    }

    @Test
    func `should put a quota with no stated window last, tightest first`() {
        let card = card("codex", login("codex", snapshot(
            quota(60, .timeLimit("MCP Usage")),
            quota(30, .session, windowHours: 5),
            quota(20, .weekly, windowHours: 24 * 7)
        )))

        #expect(card.lines.map(\.percentRemaining) == [30, 20, 60])
    }

    @Test
    func `should read the same login the ring reads`() {
        let card = card("codex",
                        login("personal", snapshot(quota(74, .session, windowHours: 5))),
                        login("work", snapshot(quota(18, .session, windowHours: 5))))

        // A product's logins are interchangeable: the rows read the one you'd work on.
        #expect(card.lines.map(\.percentRemaining) == [74])
    }

    @Test
    func `should draw nothing for a provider with no numbers`() {
        let card = card("kimi", login("kimi", nil))

        #expect(card.lines.isEmpty)
    }
}
