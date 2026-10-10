import Foundation
import Providers

/// The popover's *All* page: a card per product in the lineup, in pill order,
/// each led by the quota that runs out first
/// (docs/features/all-providers/design.md).
public struct Overview: Sendable {
    /// One card per product, in the pill order — never re-sorted by quota.
    public let cards: [OverviewCard]

    public init(cards: [OverviewCard]) {
        self.cards = cards
    }

    /// The lineup's products as cards, each login read under the person's policy.
    @MainActor
    public init(_ monitor: QuotaMonitor) {
        self.init(cards: monitor.tabs.map { tab in
            OverviewCard(id: tab.id, name: tab.name, logins: tab.accounts.map { account in
                OverviewCard.Login(
                    id: account.id,
                    name: account.displayName,
                    snapshot: monitor.usage(of: account),
                    status: monitor.status(of: account),
                    state: .init(isSyncing: account.isSyncing, failed: account.lastError != nil,
                                 needsSetup: account.needsSetup, readsUsage: account.readsUsage)
                )
            })
        })
    }

    /// All is a pill only with two products or more: one card says nothing
    /// that product's own page doesn't.
    public var isOffered: Bool { cards.count >= 2 }

    /// The header on All: the worst card's word.
    public var badge: ProviderBadgeState {
        ProviderBadgeState(of: cards.flatMap { $0.logins.map(\.state) },
                           quotaStatus: cards.compactMap(\.status).max())
    }

    /// The quota that runs out first across every card.
    public var tightest: UsageQuota? {
        cards.compactMap(\.tightest).min { $0.percentRemaining < $1.percentRemaining }
    }

    /// Cards that are critical or out — of those with numbers.
    public var critical: Int { cards.filter { ($0.status ?? .healthy) >= .critical }.count }
    /// Cards running low.
    public var warning: Int { cards.filter { $0.status == .warning }.count }
    /// Cards with numbers and room to spare.
    public var healthy: Int { cards.filter { $0.status == .healthy }.count }
}

/// One product on *All*: its word, its tightest quota and the next.
public struct OverviewCard: Identifiable, Sendable {
    /// What a card reads of one login.
    public struct Login: Sendable {
        public let id: String
        public let name: String
        public let snapshot: UsageSnapshot?
        /// Its status under the person's policy; `nil` with no numbers.
        public let status: QuotaStatus?
        public let state: ProviderBadgeState.Login

        public init(id: String, name: String, snapshot: UsageSnapshot?, status: QuotaStatus?,
                    state: ProviderBadgeState.Login) {
            self.id = id
            self.name = name
            self.snapshot = snapshot
            self.status = status
            self.state = state
        }
    }

    /// The product's id — `codex`, never `codex.<acct>`.
    public let id: String
    public let name: String
    let logins: [Login]

    public init(id: String, name: String, logins: [Login]) {
        self.id = id
        self.name = name
        self.logins = logins
    }

    /// The login whose quota runs out first.
    private var tightestOf: (login: Login, quota: UsageQuota)? {
        logins
            .compactMap { login in login.snapshot?.lowestQuota.map { (login, $0) } }
            .min { $0.quota.percentRemaining < $1.quota.percentRemaining }
    }

    /// The ring: the quota with the least left, across every login.
    public var tightest: UsageQuota? { tightestOf?.quota }

    /// The row under it: that login's next-lowest quota.
    public var next: UsageQuota? {
        guard let (login, tightest) = tightestOf, let quotas = login.snapshot?.quotas else { return nil }
        return quotas
            .filter { $0 != tightest }
            .min { $0.percentRemaining < $1.percentRemaining }
    }

    /// The tightest login's name — only when there are several to tell apart.
    public var tightestLogin: String? {
        logins.count > 1 ? tightestOf?.login.name : nil
    }

    public var loginCount: Int { logins.count }

    /// Where a tap lands: the product's first login.
    public var firstLoginId: String? { logins.first?.id }

    /// The worst login's status; `nil` while none has numbers.
    public var status: QuotaStatus? { logins.compactMap(\.status).max() }

    /// The same word the header uses: no *Healthy* without numbers (#259).
    public var badge: ProviderBadgeState {
        ProviderBadgeState(of: logins.map(\.state), quotaStatus: status)
    }
}
