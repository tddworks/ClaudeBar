import Foundation
import Testing
import Mockable
@testable import Domain
@testable import Infrastructure

/// The popover's *All* page: a card per provider, its tightest quota first
/// (docs/features/all-providers/design.md).
@MainActor
@Suite
struct OverviewTests {
    private func quota(_ left: Double, _ type: QuotaType = .session) -> UsageQuota {
        UsageQuota(percentRemaining: left, quotaType: type, providerId: "p")
    }

    private func snapshot(_ quotas: UsageQuota...) -> UsageSnapshot {
        UsageSnapshot(providerId: "p", quotas: quotas, capturedAt: Date())
    }

    private func login(_ id: String, _ snapshot: UsageSnapshot?, failed: Bool = false, needsSetup: Bool = false) -> OverviewCard.Login {
        OverviewCard.Login(id: id, name: id, snapshot: snapshot,
                           status: snapshot?.overallStatus,
                           state: .init(failed: failed, needsSetup: needsSetup))
    }

    private func card(_ id: String, _ logins: OverviewCard.Login...) -> OverviewCard {
        OverviewCard(id: id, name: id, logins: logins)
    }

    // MARK: - A card

    @Test
    func `should ring the quota with the least left and list the next one under it`() {
        let card = card("claude", login("claude", snapshot(quota(62), quota(35, .weekly), quota(9, .modelSpecific("opus")))))

        #expect(card.tightest?.percentRemaining == 9)
        #expect(card.next?.percentRemaining == 35)
    }

    @Test
    func `should ring the tightest login's quota and name that login when there are several`() {
        let card = card("codex",
                        login("personal", snapshot(quota(74), quota(58, .weekly))),
                        login("work", snapshot(quota(18), quota(41, .weekly))))

        #expect(card.tightest?.percentRemaining == 18)
        #expect(card.next?.percentRemaining == 41)
        #expect(card.tightestLogin == "work")
        #expect(card.loginCount == 2)
    }

    @Test
    func `should not name a login when the provider has only one`() {
        let card = card("claude", login("claude", snapshot(quota(50))))

        #expect(card.tightestLogin == nil)
    }

    @Test
    func `should take the worst login's status for the card`() {
        let card = card("codex",
                        login("personal", snapshot(quota(74))),
                        login("work", snapshot(quota(10))))

        #expect(card.badge == .quota(.critical))
    }

    @Test
    func `should say a provider is not set up rather than leave it out`() {
        let card = card("kimi", login("kimi", nil, failed: true, needsSetup: true))

        #expect(card.tightest == nil)
        #expect(card.badge == .notSetUp)
    }

    @Test
    func `should say a provider is unavailable when it failed with no numbers`() {
        let card = card("gemini", login("gemini", nil, failed: true))

        #expect(card.badge == .unavailable)
    }

    @Test
    func `should open a card on the provider's first login`() {
        let card = card("codex", login("codex", snapshot(quota(74))), login("codex.work", snapshot(quota(18))))

        #expect(card.firstLoginId == "codex")
    }

    // MARK: - The page

    @Test
    func `should count the providers that need a look and the healthy ones`() {
        let overview = Overview(cards: [
            card("claude", login("claude", snapshot(quota(9)))),
            card("codex", login("codex", snapshot(quota(30)))),
            card("gemini", login("gemini", snapshot(quota(80)))),
            card("copilot", login("copilot", snapshot(quota(0)))),
            card("kimi", login("kimi", nil, failed: true)),
        ])

        #expect(overview.critical == 2)
        #expect(overview.warning == 1)
        #expect(overview.healthy == 1)
    }

    @Test
    func `should show the worst provider's status in the header`() {
        let overview = Overview(cards: [
            card("claude", login("claude", snapshot(quota(80)))),
            card("codex", login("codex", snapshot(quota(30)))),
        ])

        #expect(overview.badge == .quota(.warning))
    }

    @Test
    func `should lead with the quota that runs out first across every provider`() {
        let overview = Overview(cards: [
            card("claude", login("claude", snapshot(quota(40)))),
            card("codex", login("codex", snapshot(quota(12)))),
            card("kimi", login("kimi", nil)),
        ])

        #expect(overview.tightest?.percentRemaining == 12)
    }

    @Test
    func `should offer All only with two providers or more`() {
        let one = Overview(cards: [card("claude", login("claude", snapshot(quota(80))))])
        let two = Overview(cards: [card("claude", login("claude", nil)), card("codex", login("codex", nil))])

        #expect(!one.isOffered)
        #expect(two.isOffered)
    }

    @Test
    func `should list a card per provider in the pill order`() throws {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        let monitor = QuotaMonitor(providers: kept([
            stubbedProduct("codex", probe: probe, settings: settings),
            stubbedProduct("claude", probe: probe, settings: settings),
            stubbedProduct("gemini", probe: probe, settings: settings),
        ]))

        let overview = Overview(monitor)

        #expect(overview.cards.map(\.id) == ["codex", "claude", "gemini"])
        #expect(overview.cards.allSatisfy { $0.badge == .awaitingData })
    }

    @Test
    func `should ring each provider's tightest quota once its usage arrives`() async {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(snapshot(quota(62), quota(9, .weekly)))
        let monitor = QuotaMonitor(providers: kept([
            stubbedProduct("claude", probe: probe, settings: settings),
            stubbedProduct("codex", probe: probe, settings: settings),
        ]))

        await monitor.refresh(providerId: "claude")
        let overview = Overview(monitor)

        #expect(overview.cards[0].tightest?.percentRemaining == 9)
        #expect(overview.cards[0].badge == .quota(.critical))
        #expect(overview.cards[1].tightest == nil)
    }
}

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
