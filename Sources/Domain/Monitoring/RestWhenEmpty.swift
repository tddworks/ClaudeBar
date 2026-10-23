import Foundation
import Observation
import Providers
import Quotas

/// *Rest when empty*: a product the person asked to rest is dimmed while
/// every counted login is out, and drawn as usual again at the first refresh
/// that shows room, telling the person both times. Its switch is never
/// touched: a resting product stays in the lineup, so the Monitor's own loop
/// keeps refreshing it and sees the reset.
///
/// It follows refreshes through `QuotaMonitor.onRefreshed`, so the Monitor
/// knows nothing of it. Where each product is lives in one saved `WhenEmpty`,
/// moved by `WhenEmpty.after`
/// ([design](../../../docs/features/monitoring/rest-when-empty/design.md)).
@MainActor
@Observable
public final class RestWhenEmpty {
    @ObservationIgnored private let repository: any RestWhenEmptyRepository
    @ObservationIgnored private let announcer: any RestWhenEmptyAnnouncer
    @ObservationIgnored private let now: @MainActor () -> Date

    /// The Monitor this follows, attached by `follow`.
    @ObservationIgnored private weak var monitor: QuotaMonitor?

    /// What was saved, by product id, so the views follow a change. A
    /// product missing here is read from the repository.
    private var states: [String: WhenEmpty] = [:]

    public init(repository: any RestWhenEmptyRepository, announcer: any RestWhenEmptyAnnouncer,
                now: @escaping @MainActor () -> Date = Date.init) {
        self.repository = repository
        self.announcer = announcer
        self.now = now
    }

    // MARK: - What the person asked

    /// Whether the person asked `product` to rest when empty: the card's switch.
    public func isOn(_ product: Provider) -> Bool {
        state(of: product) != nil
    }

    /// The card's switch. On, the product is watched (nothing rests until a
    /// refresh sees it empty); off, it is forgotten and drawn as usual.
    public func turn(_ on: Bool, product: Provider) {
        save(on ? (state(of: product) ?? .watching) : nil, for: product)
    }

    /// Where `product` is; `nil` while the person never asked.
    public func state(of product: Provider) -> WhenEmpty? {
        states[product.id] ?? repository.whenEmpty(forProvider: product.id)
    }

    /// Whether `product` is drawn dimmed, with *RESTING*.
    public func isResting(_ product: Provider) -> Bool {
        state(of: product)?.isResting == true
    }

    /// *Show anyway*: the page's button, the notice's, `claudebar://show-anyway`.
    /// Drawn as usual until it has had room; saved, so a relaunch keeps it.
    public func showAnyway(_ product: Provider) {
        guard isResting(product) else { return }
        save(.shownAnyway, for: product)
    }

    // MARK: - Following the Monitor

    /// Follows every refresh of `monitor`. The composition root calls this
    /// once.
    public func follow(_ monitor: QuotaMonitor) {
        self.monitor = monitor
        for product in monitor.providers.all {
            if let state = repository.whenEmpty(forProvider: product.id) { states[product.id] = state }
        }
        monitor.onRefreshed { [weak self] login in await self?.review(login) }
    }

    /// After a refresh of `login`: its product's status moves its
    /// `WhenEmpty`, and the person hears when it rests and when it is back.
    func review(_ login: Account) async {
        guard let monitor, let product = monitor.product(of: login), let state = state(of: product) else { return }
        let next = state.after(monitor.status(of: product), now: now())
        guard next != state else { return }
        save(next, for: product)
        if next.isResting {
            await announce(.resting, product)
        } else if state.isResting {
            await announce(.back, product)
        }
    }

    // MARK: - Private

    private func save(_ state: WhenEmpty?, for product: Provider) {
        repository.setWhenEmpty(state, forProvider: product.id)
        states[product.id] = state
    }

    private func announce(_ kind: RestNotice.Kind, _ product: Provider) async {
        await announcer.announce(RestNotice(kind: kind, productName: product.name, providerId: product.id))
    }
}
