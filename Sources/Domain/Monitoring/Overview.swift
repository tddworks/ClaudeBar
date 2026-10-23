import Foundation
import Providers

/// The popover's *All* page: a card per product in the lineup, in pill order,
/// each led by the quota that runs out first
/// (docs/features/monitoring/all-providers/design.md).
public struct Overview: Sendable {
    /// One card per product, in the pill order — never re-sorted by quota.
    public let cards: [OverviewCard]

    public init(cards: [OverviewCard]) {
        self.cards = cards
    }

    /// The lineup's products as cards, each unpaused login read under the
    /// person's policy. A paused login is on its product's page, never on
    /// *All* — and a product with no unpaused login has nothing to ring here,
    /// so it has no card either.
    @MainActor
    public init(_ monitor: QuotaMonitor) {
        self.init(cards: monitor.tabs.compactMap { tab in
            guard !tab.unpaused.isEmpty else { return nil }
            return OverviewCard(id: tab.id, name: tab.name, logins: tab.unpaused.map { account in
                OverviewCard.Login(
                    id: account.id,
                    name: account.displayName,
                    snapshot: monitor.usage(of: account),
                    status: monitor.status(of: account),
                    state: .init(isSyncing: account.isSyncing, failed: account.lastError != nil,
                                 needsSetup: account.needsSetup, readsUsage: account.readsUsage),
                    source: account.answeredByLabel,
                    usageHistory: account.usageHistory
                )
            },
            best: tab.provider.accounts.best?.id,
            inUse: tab.provider.inUse.flatMap { inUse in tab.unpaused.first(where: inUse.isInUse)?.id })
        })
    }

    /// All is a pill only with two products or more: one card says nothing
    /// that product's own page doesn't.
    public var isOffered: Bool { cards.count >= 2 }

    /// The header on All: the worst card's word.
    public var badge: ProviderBadgeState {
        ProviderBadgeState(of: cards.flatMap { $0.logins.map(\.state) }, quotaStatus: status)
    }

    /// The worst card's status — each product as healthy as its healthiest
    /// login; `nil` while no card has numbers.
    public var status: QuotaStatus? { cards.compactMap(\.status).max() }

    /// The card whose ring runs out first — the one All leads with.
    public var tightestCard: OverviewCard? {
        cards.compactMap { card in card.tightest.map { (card, $0) } }
            .min { $0.1.percentRemaining < $1.1.percentRemaining }?.0
    }

    /// The quota that runs out first across every card.
    public var tightest: UsageQuota? { tightestCard?.tightest }

    /// Cards that are critical or out — of those with numbers.
    public var critical: Int { cards.filter { ($0.status ?? .healthy) >= .critical }.count }
    /// Cards running low.
    public var warning: Int { cards.filter { $0.status == .warning }.count }
    /// Cards with numbers and room to spare.
    public var healthy: Int { cards.filter { $0.status == .healthy }.count }
}

/// One product on *All*: its word, its tightest quota and the next — or, in
/// **Bars**, every quota it watches as one **line** each.
public struct OverviewCard: Identifiable, Sendable {
    /// What a card reads of one login.
    public struct Login: Sendable {
        public let id: String
        public let name: String
        public let snapshot: UsageSnapshot?
        /// Its status under the person's policy; `nil` with no numbers.
        public let status: QuotaStatus?
        public let state: ProviderBadgeState.Login
        /// *via RPC* — which data source answered, when one has.
        public let source: String?
        /// Its day-by-day usage, read on the ask — `nil` when its provider
        /// declares none.
        public let usageHistory: UsageHistory?

        public init(id: String, name: String, snapshot: UsageSnapshot?, status: QuotaStatus?,
                    state: ProviderBadgeState.Login, source: String? = nil, usageHistory: UsageHistory? = nil) {
            self.id = id
            self.name = name
            self.snapshot = snapshot
            self.status = status
            self.state = state
            self.source = source
            self.usageHistory = usageHistory
        }
    }

    /// The product's id — `codex`, never `codex.<acct>`.
    public let id: String
    public let name: String
    /// Its unpaused logins, in the person's order.
    public let logins: [Login]
    /// The login with the most left — *switch to work* — as `Accounts.best` says.
    public let best: String?
    /// The login new sessions start with, as `InUse` says; `nil` with no choice.
    public let inUse: String?

    public init(id: String, name: String, logins: [Login], best: String? = nil, inUse: String? = nil) {
        self.id = id
        self.name = name
        self.logins = logins
        self.best = best
        self.inUse = inUse
    }

    /// The login the card reads: its healthiest, then the one with the most
    /// left — a product's logins are interchangeable (CANONICAL §5) — with
    /// that login's quota that runs out first.
    private var tightestOf: (login: Login, quota: UsageQuota)? {
        logins
            .compactMap { login in login.snapshot?.lowestQuota.map { (login, $0) } }
            .min { a, b in
                let (sa, sb) = (a.login.status ?? .healthy, b.login.status ?? .healthy)
                return sa != sb ? sa < sb : a.quota.percentRemaining > b.quota.percentRemaining
            }
    }

    /// The login the card reads — its healthiest, then the one with the most left.
    public var login: Login? { tightestOf?.login }

    /// The ring: the healthiest login's quota with the least left.
    public var tightest: UsageQuota? { tightestOf?.quota }

    /// The row under it: that login's next-lowest quota.
    public var next: UsageQuota? {
        guard let (login, tightest) = tightestOf, let quotas = login.snapshot?.quotas else { return nil }
        return quotas
            .filter { $0 != tightest }
            .min { $0.percentRemaining < $1.percentRemaining }
    }

    /// The name of the login the ring reads — only when there are several to tell apart.
    public var tightestLogin: String? {
        logins.count > 1 ? login?.name : nil
    }

    /// Every quota of the login this card reads — the **lines** the *Bars*
    /// page draws, instead of a card's two rows. Ordered by the window the
    /// provider **stated**, shortest first, so like sits beside like when the
    /// rows are read down the page: every session in one column, every weekly
    /// in the next. A quota whose window was never stated sorts last, tightest
    /// first; a window is never guessed from a name (CANONICAL §5).
    ///
    /// Quotas the person hides never reach here: `QuotaMonitor` hands over a
    /// snapshot with them already gone.
    public var lines: [UsageQuota] {
        guard let quotas = tightestOf?.login.snapshot?.quotas else { return [] }
        return quotas.sorted(by: readsBefore)
    }

    /// Quotas in line order: a stated window first and shorter, ties and
    /// windowless quotas by what runs out first.
    private func readsBefore(_ a: UsageQuota, _ b: UsageQuota) -> Bool {
        switch (a.window?.length, b.window?.length) {
        case let (aLength?, bLength?):
            aLength == bLength ? a.percentRemaining < b.percentRemaining : aLength < bLength
        case (_?, nil):
            true
        case (nil, _?):
            false
        case (nil, nil):
            a.percentRemaining < b.percentRemaining
        }
    }

    public var loginCount: Int { logins.count }

    /// Where a tap lands: the product's first login.
    public var firstLoginId: String? { logins.first?.id }

    /// The healthiest login's status; `nil` while none has numbers.
    public var status: QuotaStatus? { logins.compactMap(\.status).min() }

    /// The same word the header uses: no *Healthy* without numbers (#259).
    public var badge: ProviderBadgeState {
        ProviderBadgeState(of: logins.map(\.state), quotaStatus: status)
    }
}
