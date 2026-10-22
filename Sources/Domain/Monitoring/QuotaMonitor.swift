import Quotas
import DataSources
import Providers
import Foundation
import Observation

/// Events emitted during continuous monitoring
public enum MonitoringEvent: Sendable {
    /// A refresh cycle completed
    case refreshed
    /// An error occurred during refresh for a provider
    case error(providerId: String, Error)
}

/// The main domain service that coordinates quota monitoring across AI providers.
/// Providers are rich domain models that own their own snapshots.
/// QuotaMonitor coordinates refreshes; whatever follows a refresh — alerts
/// among them — observes it through `onRefreshed`.
///
/// Isolated to `@MainActor` because its `@Observable` state (`isMonitoring`,
/// `selectedProviderId`, …) is consumed by SwiftUI. This keeps the background
/// monitoring loop from mutating observable state off the main actor — the
/// crash in issue #182 — and lets the compiler reject any future off-main
/// mutation. Mirrors `SessionMonitor`, which is already `@MainActor @Observable`.
@MainActor
@Observable
public final class QuotaMonitor {
    /// The providers you keep — each with its logins, in the pane's order
    /// (CANONICAL §1). The Monitor reads them and watches; adding,
    /// deleting and ordering them is `Providers`' (TARGET §2.1).
    public let providers: Providers

    /// Clock for scheduling intervals (injectable for tests)
    private let clock: any Clock

    /// Optional power-state source for energy-aware monitoring. `nil` disables
    /// energy-awareness entirely (the plain timed loop), which is the default for
    /// tests; the app injects a real provider via the convenience init.
    private let powerStateProvider: (any PowerStateProvider)?

    /// Where the quotas each product hides are saved (#140). `nil` in tests.
    private let settingsRepository: (any ProviderSettingsRepository)?

    /// The person's status policy, read live — every status the monitor
    /// reports, and every alert it sends, is under it.
    private let readStatusPolicy: @MainActor () -> StatusPolicy

    /// Current monitoring task
    private var monitoringTask: Task<Void, Never>?

    /// Whether monitoring is active
    public private(set) var isMonitoring: Bool = false

    /// The currently selected provider ID (for UI display)
    public var selectedProviderId: String = "claude"

    /// The quotas each product hides (#140), by product id — loaded from
    /// settings, observable so every surface follows a change at once.
    private var hiddenQuotas: [String: Set<String>] = [:]

    // MARK: - Initialization

    /// Creates a QuotaMonitor over the products.
    /// Automatically validates the selected provider on initialization.
    public init(
        providers: Providers,
        clock: any Clock,
        settingsRepository: (any ProviderSettingsRepository)? = nil,
        powerStateProvider: (any PowerStateProvider)? = nil,
        statusPolicy: @escaping @MainActor () -> StatusPolicy = { .absolute }
    ) {
        self.providers = providers
        self.clock = clock
        self.powerStateProvider = powerStateProvider
        self.settingsRepository = settingsRepository
        self.readStatusPolicy = statusPolicy
        for provider in providers.all { loadHiddenQuotas(for: provider.id) }
        selectFirstEnabledIfNeeded()
    }

    // MARK: - Hidden quotas (#140)

    /// A provider's usage as every surface reads it: without the quotas the
    /// person hid for its product, so a quota they don't watch is never shown
    /// and never sets a status or an alert.
    public func usage(of provider: Account) -> UsageSnapshot? {
        provider.snapshot?.hiding(hiddenQuotaKeys(for: provider))
    }

    /// The quota keys hidden for a provider's product — shared by its accounts.
    public func hiddenQuotaKeys(for provider: Account) -> Set<String> {
        hiddenQuotas[Self.productId(of: provider)] ?? []
    }

    /// Hides or shows one quota for a provider's product, saved. Refused —
    /// `false` — when it would hide the last quota the provider reports.
    @discardableResult
    public func setQuota(_ key: String, hidden: Bool, for provider: Account) -> Bool {
        let product = Self.productId(of: provider)
        var keys = hiddenQuotas[product] ?? []
        if hidden {
            let reported = Set(provider.snapshot?.quotas.map(\.quotaType.quotaKey) ?? [])
            guard !reported.subtracting(keys).subtracting([key]).isEmpty else { return false }
            keys.insert(key)
        } else {
            keys.remove(key)
        }
        hiddenQuotas[product] = keys
        settingsRepository?.setHiddenQuotaKeys(keys, forProvider: product)
        return true
    }

    private func loadHiddenQuotas(for product: String) {
        guard hiddenQuotas[product] == nil, let keys = settingsRepository?.hiddenQuotaKeys(forProvider: product) else { return }
        hiddenQuotas[product] = keys
    }

    /// The product a lineup entry belongs to — `codex` for `codex.<acct>`.
    private static func productId(of login: Account) -> String { login.providerId }

    // MARK: - The logins

    /// Every login, on or off, in the pane's order.
    public var logins: [Account] { providers.logins }

    /// The lineup — the enabled logins of enabled providers, in the pane's
    /// order: what the pills, menu bar, refreshes and alerts show.
    public var lineup: [Account] { providers.lineup }

    /// The login with the given lineup id (`claude`, `codex.<acct>`).
    public func login(id: String) -> Account? { providers.login(id: id) }

    /// A login's product — found through the root, by the id the login names
    /// (TARGET §2.1). Ask it anything product-level about the login.
    public func product(of login: Account) -> Provider? { providers.provider(of: login) }

    /// *The name the lineup prints* for a login — its product's to say.
    public func lineupName(of login: Account) -> String {
        product(of: login)?.lineupName(of: login) ?? login.displayName
    }

    /// What setting a login up takes — its product's words.
    public func setupNotice(of login: Account) -> ProviderDefinition.Setup {
        product(of: login)?.setupNotice(of: login) ?? .fallback(for: login.displayName, error: login.lastError)
    }

    /// The dashboard for a login's plan — its product's to say.
    public func dashboardURL(of login: Account) -> URL? { product(of: login)?.dashboardURL(of: login) }

    // MARK: - Monitoring Operations

    /// Refreshes every unpaused login concurrently, each updating its own
    /// snapshot. Today's usage is *not* read: this is also the background's
    /// moment, and usage history is read with a page, never in the background.
    public func refreshAll(kind: RefreshKind = .interactive) async {
        await refresh(lineup, kind: kind)
    }

    /// The popover's page: every login it watches is refreshed, and today's
    /// usage is read with it — the moment the page is on screen (CANONICAL §1).
    /// Who is fetched is decided here, so a page draws and calls.
    public func refresh(_ tab: ProductTab, kind: RefreshKind = .interactive) async {
        await refresh(tab.unpaused, kind: kind) { await Self.read($0.usageHistory) }
    }

    /// *TODAY'S USAGE* for every unpaused login — what the *All* page and the
    /// notch read, and when they read it: with a page, never in the background.
    public func readToday() async {
        await withTaskGroup(of: Void.self) { group in
            for login in lineup {
                group.addTask { await Self.read(login.usageHistory) }
            }
        }
    }

    /// Today and the thirty days. The year is read only when a section that
    /// shows it is on screen, which tells the history itself (`readYear`).
    private static func read(_ history: UsageHistory?) async {
        await history?.read()
    }

    /// The logins, refreshed together — one place, whether it is the whole
    /// watch list or one product's page.
    private func refresh(
        _ logins: [Account],
        kind: RefreshKind,
        also: (@Sendable (Account) async -> Void)? = nil
    ) async {
        await withTaskGroup(of: Void.self) { group in
            for login in logins {
                group.addTask {
                    await self.refreshProvider(login, kind: kind)
                    await also?(login)
                }
            }
        }
    }

    /// Refreshes a single provider.
    /// `kind` defaults to `.interactive`; the background monitoring loop passes
    /// `.background` so providers can skip non-glanceable work (issue #204).
    private func refreshProvider(_ provider: Account, kind: RefreshKind = .interactive) async {
        guard let product = providers.provider(of: provider), await product.isAvailable(provider) else {
            return
        }

        do {
            // A paused login's fetch is refused — before it starts, or as it
            // lands — so nothing is recorded and there is nothing to publish.
            _ = try await product.refresh(provider, kind)
            await refreshed(provider)
        } catch {
            // The refusal (.paused) and every failure: the login holds both, in
            // `lastError`. No external observer is told.
        }
    }

    /// Tells whatever follows refreshes that `login` was refreshed.
    private func refreshed(_ login: Account) async {
        for observer in refreshObservers {
            await observer(login)
        }
    }

    /// What else reacts to a refreshed login — the Monitor's one extension
    /// point, so a feature that follows refreshes never edits the Monitor.
    @ObservationIgnored private var refreshObservers: [@MainActor (Account) async -> Void] = []

    /// Runs `observer` after every successful refresh of a login.
    public func onRefreshed(_ observer: @escaping @MainActor (Account) async -> Void) {
        refreshObservers.append(observer)
    }

    /// Refreshes a single provider by its ID. Whether it may be fetched is the
    /// product's to answer, and it answers `.paused` for a paused login
    /// (CANONICAL §5) — so no caller filters first.
    public func refresh(providerId: String, kind: RefreshKind = .interactive) async {
        guard let provider = login(id: providerId) else {
            return
        }
        await refreshProvider(provider, kind: kind)
    }

    /// Refreshes the given providers once, preserving order and removing duplicates.
    public func refresh(providerIds: [String], kind: RefreshKind = .interactive) async {
        var seen = Set<String>()
        let uniqueProviderIds = providerIds.filter { providerId in
            seen.insert(providerId).inserted
        }

        await withTaskGroup(of: Void.self) { group in
            for providerId in uniqueProviderIds {
                group.addTask {
                    await self.refresh(providerId: providerId, kind: kind)
                }
            }
        }
    }

    /// Refreshes all enabled providers except the specified one.
    public func refreshOthers(except providerId: String) async {
        let otherProviders = lineup.filter { $0.id != providerId }

        await withTaskGroup(of: Void.self) { group in
            for provider in otherProviders {
                group.addTask {
                    await self.refreshProvider(provider)
                }
            }
        }
    }

    // MARK: - Queries


    /// The lowest quota across the enabled products, each read by its login
    /// with the most left — a product's logins are interchangeable (CANONICAL §5).
    public func lowestQuota() -> UsageQuota? {
        products
            .compactMap { logins in logins.compactMap { usage(of: $0)?.lowestQuota }.max() }
            .min()
    }

    /// Returns the selected quota for a provider from enabled provider snapshots.
    public func quota(providerId: String, quotaKey: String) -> UsageQuota? {
        lineup
            .first { $0.id == providerId }?
            .snapshot?
            .quota(forKey: quotaKey)
    }

    /// Returns the menu bar percentage display for a provider/quota selection.
    public func menuBarPercentageDisplay(
        providerId: String,
        quotaKey: String,
        mode: UsageDisplayMode,
        burnRateWarningEnabled: Bool = false,
        burnRateThreshold: Double = 1.5
    ) -> MenuBarPercentageDisplay? {
        guard let quota = quota(providerId: providerId, quotaKey: quotaKey) else {
            return nil
        }

        return MenuBarPercentageDisplay(
            quota: quota,
            mode: mode,
            burnRateWarningEnabled: burnRateWarningEnabled,
            burnRateThreshold: burnRateThreshold
        )
    }

    /// Returns the menu bar duration display for a provider/quota selection.
    /// Sibling to `menuBarPercentageDisplay`; both use the same selectors.
    public func menuBarDurationDisplay(
        providerId: String,
        quotaKey: String,
        burnRateWarningEnabled: Bool = false,
        burnRateThreshold: Double = 1.5
    ) -> MenuBarDurationDisplay? {
        guard let quota = quota(providerId: providerId, quotaKey: quotaKey) else {
            return nil
        }

        return MenuBarDurationDisplay(
            quota: quota,
            burnRateWarningEnabled: burnRateWarningEnabled,
            burnRateThreshold: burnRateThreshold
        )
    }

    /// Additional providers use their first quota and include a name so adjacent
    /// readouts remain distinguishable. Enabled providers awaiting data keep a placeholder.
    public func additionalMenuBarLabels(
        providerIds: [String],
        configurations: [String: MenuBarProviderSettings] = [:],
        showPercentage: Bool,
        showDuration: Bool,
        mode: UsageDisplayMode,
        burnRateWarningEnabled: Bool = false,
        burnRateThreshold: Double = 1.5
    ) -> [MenuBarProviderLabel] {
        guard showPercentage || showDuration else { return [] }
        var seen = Set<String>()
        return providerIds.filter { seen.insert($0).inserted }.prefix(2).compactMap { id in
            guard let provider = lineup.first(where: { $0.id == id }) else { return nil }
            let config = configurations[id] ?? MenuBarProviderSettings()
            let key = config.primaryQuotaKey.isEmpty
                ? usage(of: provider)?.quotas.first?.quotaType.quotaKey : config.primaryQuotaKey
            guard let key,
                  let label = menuBarLabel(
                    providerId: id, primaryQuotaKey: key, secondaryQuotaKey: config.secondaryQuotaKey,
                    showPercentage: showPercentage, showDuration: showDuration,
                    mode: mode, burnRateWarningEnabled: burnRateWarningEnabled,
                    burnRateThreshold: burnRateThreshold
                  ) else {
                return MenuBarProviderLabel(providerId: id, providerName: lineupName(of: provider),
                                            label: MenuBarLabel(text: "—", status: .healthy))
            }
            return MenuBarProviderLabel(providerId: id, providerName: lineupName(of: provider), label: label,
                                        stacked: config.stacked, stackedSize: MenuBarStackedSize(storedRawValue: config.stackedSize))
        }
    }

    /// Builds the fully composed menu bar label for one or two quota windows.
    ///
    /// The primary window renders exactly as the single-window label always has
    /// (percentage and/or duration joined by " · "). When `secondaryQuotaKey` is
    /// non-empty and differs from the primary, a second window is appended: each
    /// window is prefixed with the quota's `menuBarTitle` when the probe set one
    /// (a condensed form of labels too wide for the menu bar), otherwise its
    /// `QuotaType.shortLabel`, and the two are joined by " | ", e.g.
    /// "5h 12% | 7d 34%". The status is the most severe of the
    /// shown windows, and each window is also exposed individually via
    /// `MenuBarLabel.segments` for renderers that draw them on separate lines.
    ///
    /// Returns nil when neither percentage nor duration is enabled, or when no
    /// quota data is available for the requested windows.
    public func menuBarLabel(
        providerId: String,
        primaryQuotaKey: String,
        secondaryQuotaKey: String = "",
        showPercentage: Bool,
        showDuration: Bool,
        mode: UsageDisplayMode,
        burnRateWarningEnabled: Bool = false,
        burnRateThreshold: Double = 1.5
    ) -> MenuBarLabel? {
        let primaryQuotaKey = primaryQuotaKey.isEmpty
            ? (lineup.first { $0.id == providerId }.flatMap { usage(of: $0) }?.quotas.first?.quotaType.quotaKey ?? "")
            : primaryQuotaKey
        func segment(forQuotaKey quotaKey: String) -> (text: String, status: QuotaStatus)? {
            let percentage = showPercentage
                ? menuBarPercentageDisplay(
                    providerId: providerId,
                    quotaKey: quotaKey,
                    mode: mode,
                    burnRateWarningEnabled: burnRateWarningEnabled,
                    burnRateThreshold: burnRateThreshold
                )
                : nil
            let duration = showDuration
                ? menuBarDurationDisplay(
                    providerId: providerId,
                    quotaKey: quotaKey,
                    burnRateWarningEnabled: burnRateWarningEnabled,
                    burnRateThreshold: burnRateThreshold
                )
                : nil

            switch (percentage, duration) {
            case let (.some(percentage), .some(duration)):
                return ("\(percentage.text) · \(duration.text)", percentage.status)
            case let (.some(percentage), .none):
                return (percentage.text, percentage.status)
            case let (.none, .some(duration)):
                return (duration.text, duration.status)
            case (.none, .none):
                return nil
            }
        }

        let primary = segment(forQuotaKey: primaryQuotaKey)
        let secondary = (!secondaryQuotaKey.isEmpty && secondaryQuotaKey != primaryQuotaKey)
            ? segment(forQuotaKey: secondaryQuotaKey)
            : nil

        switch (primary, secondary) {
        case let (.some(primary), .some(secondary)):
            // Window prefix: the quota's own condensed menu-bar title wins
            // (probes set it when the full label is too wide, e.g. a long
            // account discriminator), then the type's short label.
            func windowPrefix(forQuotaKey quotaKey: String) -> String {
                if let title = quota(providerId: providerId, quotaKey: quotaKey)?.menuBarTitle {
                    return title
                }
                return QuotaType(quotaKey: quotaKey)?.shortLabel ?? quotaKey
            }
            let primaryLabel = windowPrefix(forQuotaKey: primaryQuotaKey)
            let secondaryLabel = windowPrefix(forQuotaKey: secondaryQuotaKey)
            // Each window becomes its own segment (prefixed text + that
            // window's status) so stacked rendering can draw and tint them
            // independently; the joined text stays the canonical single-line
            // form and doubles as the tooltip.
            let primarySegment = MenuBarLabel.Segment(
                text: "\(primaryLabel) \(primary.text)",
                status: primary.status
            )
            let secondarySegment = MenuBarLabel.Segment(
                text: "\(secondaryLabel) \(secondary.text)",
                status: secondary.status
            )
            return MenuBarLabel(
                text: "\(primarySegment.text) | \(secondarySegment.text)",
                status: max(primary.status, secondary.status),
                segments: [primarySegment, secondarySegment]
            )
        case let (.some(primary), .none):
            return MenuBarLabel(text: primary.text, status: primary.status)
        case let (.none, .some(secondary)):
            return MenuBarLabel(text: secondary.text, status: secondary.status)
        case (.none, .none):
            return nil
        }
    }

    /// HOW STRICT TO BE — the person's policy (Settings → General).
    public var statusPolicy: StatusPolicy { readStatusPolicy() }

    /// The worst product's status, each product as healthy as its healthiest
    /// login (CANONICAL §5): its logins are interchangeable, products are not.
    public var overallStatus: QuotaStatus {
        products
            .compactMap { logins in logins.compactMap { status(of: $0) }.min() }
            .max() ?? .healthy
    }

    /// The lineup, a product at a time: each enabled product's unpaused logins.
    private var products: [[Account]] {
        providers.all.filter(\.isEnabled).map(\.accounts.unpaused)
    }

    // MARK: - Selection

    /// The currently selected provider (from enabled providers)
    public var selectedLogin: Account? {
        lineup.first { $0.id == selectedProviderId }
    }

    /// Status of the currently selected provider (for menu bar icon)
    public var selectedProviderStatus: QuotaStatus {
        selectedLogin.flatMap { usage(of: $0) }?.overallStatus(under: statusPolicy) ?? .healthy
    }

    /// Whether any provider is currently refreshing
    public var isRefreshing: Bool {
        logins.contains { $0.isSyncing }
    }

    /// Selects a provider by ID (must be enabled)
    public func selectProvider(id: String) {
        if lineup.contains(where: { $0.id == id }) {
            selectedProviderId = id
        }
    }

    /// The popover's pills: one per product whose switch is on, holding every
    /// login of it — the tabs follow the persisted order (issue #141), not the
    /// registration order.
    public var tabs: [ProductTab] { ProductTab.tabs(in: providers) }

    /// Settings → Providers: every product, on or off, each with all its
    /// logins, in the pane's order (CANONICAL §1: the product's switch).
    public var productTabs: [ProductTab] { ProductTab.everyProduct(in: providers) }

    /// A product's switch — off hides every login of it and keeps them; the
    /// selection moves off a product that is turned off.
    public func setProductEnabled(_ tab: ProductTab, enabled: Bool) {
        tab.provider.isEnabled = enabled
        if !enabled { selectFirstEnabledIfNeeded() }
    }

    /// *Pause* — the login is out of every judgement and keeps what it last showed
    /// (`Account` owns that; CANONICAL §5). The Monitor's part is the
    /// selection: it moves off a login no page is showing any more.
    public func pause(_ account: Account) {
        account.pause()
        selectFirstEnabledIfNeeded()
    }

    /// *Resume* — the login counts again, from the numbers it kept.
    public func resume(_ account: Account) {
        account.resume()
    }

    /// The tab the selected login belongs to.
    public var selectedTab: ProductTab? { tabs.first { $0.contains(selectedProviderId) } }

    /// The unpaused logins on the selected tab: what the page's cards
    /// show and what judges anything.
    public var selectedLogins: [Account] { selectedTab?.unpaused ?? selectedLogin.map { [$0] } ?? [] }

    /// One login's quota status under the person's policy; `nil` with no usage.
    public func status(of login: Account) -> QuotaStatus? {
        usage(of: login)?.overallStatus(under: statusPolicy)
    }

    /// The selected tab's status: its healthiest unpaused login's, for a
    /// product's logins are interchangeable (CANONICAL §5); `nil` while no
    /// unpaused login has usage.
    public var selectedTabStatus: QuotaStatus? { selectedLogins.compactMap { status(of: $0) }.min() }

    /// What the popover's header says about the selected tab — the tab's own
    /// answer, with the status the person's policy gives its unpaused logins.
    public var selectedBadge: ProviderBadgeState {
        // No page, no badge — an empty cast, since `[]` fits both login shapes.
        guard let tab = selectedTab else { return ProviderBadgeState(of: [Account](), quotaStatus: nil) }
        return ProviderBadgeState(of: tab, quotaStatus: selectedTabStatus)
    }

    /// Selects the tab in the given 1-based slot, counted the way the popover
    /// lists them (⌘1 is the first pill), opening on its first login — the one
    /// a paused-only tab has is paused, and its page is still that product's.
    /// The slots follow the persisted order (issue #141). A slot with no tab
    /// leaves the selection alone.
    public func selectProvider(atPosition position: Int) {
        let tabs = tabs
        guard tabs.indices.contains(position - 1), let first = tabs[position - 1].logins.first else { return }
        selectedProviderId = first.id
    }

    /// Selects the first enabled provider if the selection is on no page the
    /// popover still shows — a product turned off, or a login gone. Called on
    /// initialization, and whenever a login or a product leaves the page.
    private func selectFirstEnabledIfNeeded() {
        if tabs.contains(where: { $0.contains(selectedProviderId) }) { return }
        if let firstEnabled = lineup.first {
            selectedProviderId = firstEnabled.id
        }
    }

    // MARK: - Continuous Monitoring

    /// The hard lower bound on the monitoring interval. Background refresh must
    /// never poll faster than once a minute (energy — issue #67).
    public static let minimumInterval: Duration = .seconds(60)

    /// How much to stretch the background cadence while on battery, to reduce
    /// drain when unplugged (issue #204). Applied on top of the effective
    /// interval each tick, so plugging back in restores the normal cadence.
    public static let batteryIntervalMultiplier: Int = 2

    /// Clamps a requested interval to the 1-minute floor. Exposed so the floor
    /// can be unit-tested directly and so every caller funnels through one rule.
    public static func clampedInterval(_ interval: Duration) -> Duration {
        max(interval, minimumInterval)
    }

    /// The actual sleep interval for one background monitoring tick: the
    /// requested interval clamped to the 1-minute floor, then raised to the
    /// slowest provider-imposed `backgroundRefreshFloor` in the active set.
    ///
    /// The slowest floor wins for a multi-provider set (e.g. Claude in API mode
    /// floors the loop at 15 min — issue #204), which is acceptable for a
    /// background glance. Pure and static so it can be unit-tested directly.
    public static func effectiveInterval(requested: Duration, floors: [Duration]) -> Duration {
        max(clampedInterval(requested), floors.max() ?? .zero)
    }

    /// Refreshes only the currently selected provider.
    public func refreshSelected(kind: RefreshKind = .interactive) async {
        await refresh(providerId: selectedProviderId, kind: kind)
    }

    /// The `backgroundRefreshFloor`s declared by the providers refreshed each
    /// cycle — the supplied set, or the currently selected provider when none is
    /// given (mirroring how `startMonitoring` chooses what to refresh).
    ///
    /// Resolved fresh each tick so a live probe-mode switch (CLI↔API) is honored
    /// without restarting the loop: the menu-bar refresh key doesn't observe
    /// `probeMode`, so the cadence would otherwise stay stale (issue #204).
    private func backgroundRefreshFloors(for providerIds: [String]?) -> [Duration] {
        let ids = providerIds ?? [selectedProviderId]
        return ids.compactMap { login(id: $0).flatMap(product(of:))?.backgroundRefreshFloor }
    }

    /// Starts continuous monitoring at the specified interval.
    /// By default, refreshes the currently selected provider each cycle to minimize energy usage.
    /// When provider IDs are supplied, refreshes that de-duplicated provider set each cycle.
    /// The effective cadence is the requested interval clamped to a 1-minute
    /// floor, then raised to the slowest provider-imposed `backgroundRefreshFloor`
    /// in the active set (recomputed each tick so a live probe-mode switch is
    /// honored without restarting). Returns an AsyncStream of monitoring events.
    public func startMonitoring(
        interval: Duration = .seconds(60),
        providerIds: [String]? = nil
    ) -> AsyncStream<MonitoringEvent> {
        // Stop any existing monitoring
        monitoringTask?.cancel()

        isMonitoring = true

        return AsyncStream { continuation in
            let task = Task {
                // Iterator over power transitions; nil when energy-awareness is
                // disabled (no power provider), so the loop below behaves exactly
                // like the plain timed loop in that case.
                var powerEvents = self.powerStateProvider?.events().makeAsyncIterator()

                while !Task.isCancelled {
                    // Energy awareness: while the display/system is asleep, pause
                    // — no refresh and no probe subprocess spawn — and wait for
                    // the next wake event so we can refresh immediately when the
                    // user returns (issue #204). A nil power provider skips this
                    // entirely. `AsyncStream.next()` resumes with nil on task
                    // cancellation, so `stopMonitoring()` unparks the loop.
                    while let power = self.powerStateProvider,
                          power.isDisplayAsleep,
                          !Task.isCancelled {
                        guard await powerEvents?.next() != nil else { break }
                        // Re-check `isDisplayAsleep`: a `.didWake` clears it and
                        // we fall through to an immediate refresh.
                    }
                    if Task.isCancelled { break }

                    // The continuous loop is the background poll: refresh with
                    // `.background` so providers skip non-glanceable work, and
                    // bind a low (`.utility`) QoS so any CLI subprocess spawned
                    // during the refresh runs on efficiency cores / throttled —
                    // both keep idle energy use low (issue #204).
                    await FetchContext.$qualityOfService.withValue(.utility) {
                        if let providerIds {
                            await self.refresh(providerIds: providerIds, kind: .background)
                        } else {
                            await self.refreshSelected(kind: .background)
                        }
                    }
                    continuation.yield(.refreshed)

                    // Compute the sleep each tick: the requested interval clamped
                    // to the 1-minute floor, then raised to any provider-imposed
                    // background floor (e.g. Claude API → 15 min). Resolved per
                    // tick so a live CLI↔API switch is honored without restarting.
                    let floors = self.backgroundRefreshFloors(for: providerIds)
                    var sleepInterval = Self.effectiveInterval(requested: interval, floors: floors)

                    // Stretch the cadence while on battery to reduce drain (#204).
                    if self.powerStateProvider?.isOnBattery == true {
                        sleepInterval = sleepInterval * Self.batteryIntervalMultiplier
                    }

                    do {
                        try await clock.sleep(for: sleepInterval)
                    } catch {
                        break
                    }
                }
                continuation.finish()
            }

            self.monitoringTask = task

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Stops continuous monitoring
    public func stopMonitoring() {
        isMonitoring = false
        monitoringTask?.cancel()
        monitoringTask = nil
    }
}
