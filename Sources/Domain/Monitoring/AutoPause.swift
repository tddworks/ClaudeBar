import Foundation
import Observation
import Providers
import Quotas

/// *Auto-pause on empty* — a product whose every counted login is depleted
/// turns its own switch off, once, and turns it back on at the first refresh
/// that shows room again, telling the person both times. The person asks per
/// product, once: the instruction is off until turned on, an off ClaudeBar
/// made is marked as its own, and the person's own off is never touched.
///
/// It follows refreshes through `QuotaMonitor.onRefreshed`, so the Monitor
/// knows nothing of it — and it keeps one quiet loop per waiting product,
/// because the app loop never refreshes a product that is off
/// ([design](../../../docs/features/monitoring/auto-pause/design.md)).
@MainActor
@Observable
public final class AutoPause {
    /// The settings keys, under `providers.<id>.*` in settings.json: the
    /// standing instruction, and the marker that says an off was ClaudeBar's
    /// own — the one fact that separates its off from the person's.
    private static let onKey = "autoPause"
    private static let markerKey = "autoPaused"

    /// How often the quiet loop asks a watched product whether the reset
    /// came — before the Monitor's minute floor and any product's.
    private static let pollInterval: Duration = .seconds(60)

    @ObservationIgnored private let settings: any ProviderSettingsRepository
    @ObservationIgnored private let announcer: any AutoPauseAnnouncer
    @ObservationIgnored private let clock: any Clock

    /// The Monitor this follows — attached by `follow`, or by a test that
    /// drives `review` and `sweep` by hand.
    @ObservationIgnored private weak var monitor: QuotaMonitor?

    /// The quiet loop per watched product.
    @ObservationIgnored private var watchers: [String: Task<Void, Never>] = [:]

    /// The crossing memory: seen empty since the last recovery, per product.
    /// In memory, like `StatusAlerts`' last statuses; the marker is its
    /// durable half, and `adopt` restores one from the other.
    @ObservationIgnored private var wasDepleted: Set<String> = []

    /// What `adopt` found still waiting, whose loops `follow` starts — adopt
    /// decides nothing and starts nothing.
    @ObservationIgnored private var toResume: Set<String> = []

    /// How often the instructions and markers have changed. The settings
    /// file isn't observable, so the cards read this — a turn redraws what
    /// the file alone can't show.
    private var revision = 0

    /// Creates the follower over the person's settings, the one who tells,
    /// and the clock the quiet loop sleeps on.
    public init(settings: any ProviderSettingsRepository, announcer: any AutoPauseAnnouncer,
                clock: any Clock) {
        self.settings = settings
        self.announcer = announcer
        self.clock = clock
    }

    // MARK: - The instruction

    /// Whether the person asked `product` to turn itself off when empty.
    public func isOn(_ product: Provider) -> Bool {
        _ = revision
        settings.isOn(Self.onKey, forProvider: product.id) ?? false
    }

    /// The setting's switch. Turning it on arms the standing instruction —
    /// nothing happens until a crossing. Turning it off un-arms: the wait is
    /// forgotten and, where ClaudeBar held the product off, the product goes
    /// back on — the person's own off is left off.
    public func turn(_ on: Bool, product: Provider) {
        settings.setOn(on, Self.onKey, forProvider: product.id)
        revision += 1
        guard !on, isMarked(product) else { return }
        turnBackOn(product)
    }

    // MARK: - Waiting

    /// Whether ClaudeBar turned `product` off and is watching for its reset —
    /// the row's *Waiting for a reset*.
    public func isWaiting(_ product: Provider) -> Bool {
        _ = revision
        !product.isEnabled && isMarked(product) && isOn(product)
    }

    /// *Turn back on* — the person, one click: the notice's button, or
    /// `claudebar://enable`. The wait is over and the product is on. The
    /// standing instruction stays; the crossing memory keeps it from pausing
    /// again until the product has recovered and emptied again.
    public func turnBackOn(_ product: Provider) {
        clearMarker(for: product)
        stopWatching(product)
        if !product.isEnabled { setEnabled(product, true) }
    }

    // MARK: - Following the Monitor

    /// Follows every refresh of `monitor`, adopts what a previous launch
    /// left waiting, and starts the quiet loops. The composition root calls
    /// this once; nothing else starts work.
    public func follow(_ monitor: QuotaMonitor) {
        attach(monitor)
        monitor.onRefreshed { [weak self] login in await self?.review(login) }
        adopt()
        let resuming = monitor.productTabs.map(\.provider).filter { toResume.contains($0.id) }
        toResume = []
        for product in resuming { startLoop(product) }
    }

    /// Points the follower at its Monitor — `follow`'s first step; tests call
    /// it alone and drive `review` and `sweep` by hand.
    func attach(_ monitor: QuotaMonitor) {
        self.monitor = monitor
    }

    /// Reads what a previous launch left behind, before anything refreshes:
    /// a product off with the marker and the instruction is still waiting —
    /// `follow` starts its loop. A stale marker — the person turned the
    /// product on, or withdrew the instruction — is cleaned up quietly, and
    /// the crossing remembered, so their re-enable is never undone behind
    /// their back. The person's own off (no marker) is left alone. Says
    /// nothing, starts nothing.
    func adopt() {
        guard let monitor else { return }
        for product in monitor.productTabs.map(\.provider) where isMarked(product) {
            wasDepleted.insert(product.id)
            if !product.isEnabled, isOn(product) {
                toResume.insert(product.id)
            } else {
                clearMarker(for: product)
                stopWatching(product)
            }
        }
    }

    /// After a refresh of `login`: the crossing, the recovery, the
    /// un-arming. Everything is judged through the Monitor's product status —
    /// the person's policy, hidden quotas and paused logins left out — so the
    /// watcher never keeps its own copy of *empty*.
    public func review(_ login: Account) async {
        guard let monitor, let product = monitor.product(of: login) else { return }
        let status = monitor.status(of: product)
        if product.isEnabled {
            await reviewEnabled(product, status)
        } else if isMarked(product) {
            await reviewWaiting(product, status)
        }
    }

    /// The product is on: only the crossing acts — the instruction on, seen
    /// empty, and not seen empty since the last recovery.
    private func reviewEnabled(_ product: Provider, _ status: QuotaStatus?) async {
        if isMarked(product) {
            // The person turned it back on while ClaudeBar wasn't looking:
            // the wait is over, and it is never announced.
            clearMarker(for: product)
            stopWatching(product)
            wasDepleted.insert(product.id)
        }
        guard status == .depleted else {
            wasDepleted.remove(product.id)
            return
        }
        guard isOn(product), !wasDepleted.contains(product.id) else { return }
        wasDepleted.insert(product.id)
        setMarker(for: product)
        setEnabled(product, false)
        await announce(.turnedOff, product)
        startLoop(product)
    }

    /// ClaudeBar's own off: the recovery is observed — a refresh must show
    /// room, never a failed look — and a withdrawn instruction is honoured
    /// without touching the person's off.
    private func reviewWaiting(_ product: Provider, _ status: QuotaStatus?) async {
        guard isOn(product) else {
            // The instruction was withdrawn while ClaudeBar wasn't looking:
            // leave the person's off alone, forget the wait, say nothing.
            clearMarker(for: product)
            stopWatching(product)
            wasDepleted.remove(product.id)
            return
        }
        guard let status, status != .depleted else { return }
        clearMarker(for: product)
        wasDepleted.remove(product.id)
        stopWatching(product)
        setEnabled(product, true)
        await announce(.turnedOn, product)
    }

    // MARK: - The quiet loop

    /// One quiet tick of the wait: refreshes the watched product's logins in
    /// the background — the app loop never does, for an off product isn't in
    /// the lineup — and lets `review`, through `onRefreshed`, read the answer.
    public func sweep(_ product: Provider) async {
        guard let monitor else { return }
        await monitor.refresh(providerIds: product.accounts.map(\.id), kind: .background)
    }

    private func startLoop(_ product: Provider) {
        guard watchers[product.id] == nil else { return }
        watchers[product.id] = Task { [weak self] in
            await self?.waitForReset(product)
        }
    }

    private func waitForReset(_ product: Provider) async {
        while !Task.isCancelled, isWaiting(product) {
            await sweep(product)
            let floors = product.backgroundRefreshFloor.map { [$0] } ?? []
            let interval = QuotaMonitor.effectiveInterval(requested: Self.pollInterval, floors: floors)
            try? await clock.sleep(for: interval)
        }
    }

    private func stopWatching(_ product: Provider) {
        watchers[product.id]?.cancel()
        watchers[product.id] = nil
    }

    // MARK: - Private

    /// The marker is on: ClaudeBar turned this product off.
    private func isMarked(_ product: Provider) -> Bool {
        settings.isOn(Self.markerKey, forProvider: product.id) == true
    }

    /// Marks an off as ClaudeBar's own — saved, so the wait survives a relaunch.
    private func setMarker(for product: Provider) {
        settings.setOn(true, Self.markerKey, forProvider: product.id)
        revision += 1
    }

    /// The wait is over — whatever turn of the person's said so.
    private func clearMarker(for product: Provider) {
        settings.setOn(false, Self.markerKey, forProvider: product.id)
        revision += 1
    }

    /// The flip itself — through the Monitor, which owns the selection.
    private func setEnabled(_ product: Provider, _ enabled: Bool) {
        guard let monitor, let tab = monitor.productTabs.first(where: { $0.id == product.id }) else { return }
        monitor.setProductEnabled(tab, enabled: enabled)
    }

    /// The person hears it once, with the one-click link.
    private func announce(_ kind: AutoPauseNotice.Kind, _ product: Provider) async {
        await announcer.announce(AutoPauseNotice(kind: kind, productName: product.name, providerId: product.id))
    }
}
