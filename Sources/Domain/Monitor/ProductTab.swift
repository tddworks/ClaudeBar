import Foundation
import Providers

/// A pill in the popover: one product with **every** login of it — so three
/// Claude logins are one *Claude* tab, side by side, not three tabs. The
/// logins come in the order the person gave them, watched and paused: a
/// paused login is on the page with a *Resume* and out of every judgement
/// (docs/features/multi-account/design.md §3.5).
@MainActor
public struct ProductTab: Identifiable {
    /// The product's id — `codex`, never `codex.<acct>`.
    public let id: String
    public let name: String
    /// The product.
    public let provider: Provider
    /// Every login of it, in the person's order.
    public let logins: [Account]
    /// The ones being watched — the page's chips and cards, and everything
    /// that judges a login. The product's own lists, never a filter here.
    public let watched: [Account]
    /// The ones paused: the page's PAUSED rows, and nothing else.
    public let paused: [Account]

    init(provider: Provider) {
        self.id = provider.id
        self.name = provider.name
        self.provider = provider
        self.logins = Array(provider.accounts)
        self.watched = provider.accounts.watched
        self.paused = provider.accounts.paused
    }

    /// The product's own switch (CANONICAL §1) — off takes the whole product,
    /// its tab included, out of the popover.
    public var isEnabled: Bool { provider.isEnabled }

    /// Whether the product's page is its logins rather than a single login's
    /// card: it is once there are several to tell apart, and whenever none is
    /// watched — there is nothing else for the page to say.
    public var showsAccountPages: Bool { logins.count > 1 || watched.isEmpty }

    /// A login's name on the product's row — only when there are several to
    /// tell apart; one login is just the product.
    public func loginName(_ login: Account) -> String? {
        logins.count > 1 ? login.displayName : nil
    }

    /// What the product's page configures: its plain login, whose id the
    /// configuration is keyed by.
    public var page: Account { provider.defaultAccount }

    public func contains(_ lineupId: String) -> Bool {
        logins.contains { $0.id == lineupId }
    }

    /// The popover's tabs: every product whose switch is on, with every login
    /// of it. Turning a product off is what takes its tab away.
    public static func tabs(in providers: Providers) -> [ProductTab] {
        providers.all.filter(\.isEnabled).map { ProductTab(provider: $0) }
    }

    /// Settings → Providers: every product, on or off, each with all its logins.
    public static func everyProduct(in providers: Providers) -> [ProductTab] {
        providers.all.map { ProductTab(provider: $0) }
    }
}
