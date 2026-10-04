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
/// QuotaMonitor coordinates refreshes and alerts users when status changes.
///
/// Isolated to `@MainActor` because its `@Observable` state (`isMonitoring`,
/// `selectedProviderId`, …) is consumed by SwiftUI. This keeps the background
/// monitoring loop from mutating observable state off the main actor — the
/// crash in issue #182 — and lets the compiler reject any future off-main
/// mutation. Mirrors `SessionMonitor`, which is already `@MainActor @Observable`.
@MainActor
@Observable
public final class QuotaMonitor {
    /// The providers repository (internal - access via delegation methods)
    private let providers: any AIProviderRepository

    /// Optional alerter for quota changes (e.g., system notifications)
    private let alerter: (any QuotaAlerter)?

    /// Clock for scheduling intervals (injectable for tests)
    private let clock: any Clock

    /// Optional power-state source for energy-aware monitoring. `nil` disables
    /// energy-awareness entirely (the plain timed loop), which is the default for
    /// tests; the app injects a real provider via the convenience init.
    private let powerStateProvider: (any PowerStateProvider)?

    /// Settings repository the user's provider order is read from and written
    /// to. `nil` (tests) keeps the registration order everywhere.
    private let settingsRepository: (any ProviderSettingsRepository)?

    /// The persisted provider order (provider IDs), empty when the user never
    /// reordered. Observable state: mutating it re-renders every view that
    /// reads `allProviders`/`enabledProviders`.
    private var storedProviderOrder: [String] = []

    /// The person's status policy, read live — every status the monitor
    /// reports, and every alert it sends, is under it.
    private let readStatusPolicy: @MainActor () -> StatusPolicy

    /// Previous status for change detection
    private var previousStatuses: [String: QuotaStatus] = [:]

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

    /// Creates a QuotaMonitor with a provider repository.
    /// Automatically validates the selected provider on initialization.
    /// When `settingsRepository` is given, providers are presented in the
    /// persisted order (issue #141); unlisted IDs keep their registration
    /// position and disabled providers are skipped by `enabledProviders`.
    public init(
        providers: any AIProviderRepository,
        alerter: (any QuotaAlerter)? = nil,
        clock: any Clock,
        settingsRepository: (any ProviderSettingsRepository)? = nil,
        powerStateProvider: (any PowerStateProvider)? = nil,
        statusPolicy: @escaping @MainActor () -> StatusPolicy = { .absolute }
    ) {
        self.providers = providers
        self.alerter = alerter
        self.clock = clock
        self.powerStateProvider = powerStateProvider
        self.settingsRepository = settingsRepository
        if let settingsRepository {
            storedProviderOrder = settingsRepository.providerOrder()
        }
        self.readStatusPolicy = statusPolicy
        for provider in providers.all { loadHiddenQuotas(for: provider) }
        selectFirstEnabledIfNeeded()
    }

    // MARK: - Hidden quotas (#140)

    /// A provider's usage as every surface reads it: without the quotas the
    /// person hid for its product, so a quota they don't watch is never shown
    /// and never sets a status or an alert.
    public func usage(of provider: any AIProvider) -> UsageSnapshot? {
        provider.snapshot?.hiding(hiddenQuotaKeys(for: provider))
    }

    /// The quota keys hidden for a provider's product — shared by its accounts.
    public func hiddenQuotaKeys(for provider: any AIProvider) -> Set<String> {
        hiddenQuotas[Self.productId(of: provider)] ?? []
    }

    /// Hides or shows one quota for a provider's product, saved. Refused —
    /// `false` — when it would hide the last quota the provider reports.
    @discardableResult
    public func setQuota(_ key: String, hidden: Bool, for provider: any AIProvider) -> Bool {
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

    private func loadHiddenQuotas(for provider: any AIProvider) {
        let product = Self.productId(of: provider)
        guard hiddenQuotas[product] == nil, let keys = settingsRepository?.hiddenQuotaKeys(forProvider: product) else { return }
        hiddenQuotas[product] = keys
    }

    /// The product a lineup entry belongs to — `codex` for `codex.<acct>`.
    private static func productId(of provider: any AIProvider) -> String {
        (provider as? Account)?.provider.id ?? provider.id
    }

    // MARK: - Monitoring Operations

    /// Refreshes all enabled providers concurrently.
    /// Each provider updates its own snapshot.
    /// Disabled providers are skipped.
    public func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for provider in providers.enabled {
                group.addTask {
                    await self.refreshProvider(provider)
                }
            }
        }
    }

    /// Refreshes a single provider.
    /// `kind` defaults to `.interactive`; the background monitoring loop passes
    /// `.background` so providers can skip non-glanceable work (issue #204).
    private func refreshProvider(_ provider: any AIProvider, kind: RefreshKind = .interactive) async {
        guard await provider.isAvailable() else {
            return
        }

        do {
            let snapshot = try await provider.refresh(kind)
            await handleSnapshotUpdate(provider: provider, snapshot: snapshot)
        } catch {
            // Provider stores error in lastError - no need for external observer
        }
    }

    /// Handles snapshot update and alerts user if status changed
    private func handleSnapshotUpdate(provider: any AIProvider, snapshot: UsageSnapshot) async {
        let previousStatus = previousStatuses[provider.id] ?? .healthy
        // A quota the person hid doesn't page them.
        let newStatus = snapshot.hiding(hiddenQuotaKeys(for: provider)).overallStatus(under: statusPolicy)

        previousStatuses[provider.id] = newStatus

        // Alert user only if status changed
        if previousStatus != newStatus, let alerter = alerter {
            await alerter.alert(
                providerId: provider.id,
                previousStatus: previousStatus,
                currentStatus: newStatus
            )
        }
    }

    /// Refreshes a single provider by its ID.
    public func refresh(providerId: String, kind: RefreshKind = .interactive) async {
        guard let provider = providers.provider(id: providerId) else {
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
        let otherProviders = providers.enabled.filter { $0.id != providerId }

        await withTaskGroup(of: Void.self) { group in
            for provider in otherProviders {
                group.addTask {
                    await self.refreshProvider(provider)
                }
            }
        }
    }

    // MARK: - Queries

    /// Returns the provider with the given ID
    public func provider(for id: String) -> (any AIProvider)? {
        providers.provider(id: id)
    }

    /// Returns all providers in the persisted order (registration order when
    /// the user never reordered).
    public var allProviders: [any AIProvider] {
        ordered(providers.all)
    }

    /// Returns only enabled providers, in the persisted order.
    public var enabledProviders: [any AIProvider] {
        ordered(providers.enabled)
    }

    /// Sorts the given providers by the persisted order. Listed IDs come first
    /// in stored sequence; unlisted IDs keep their registration position after
    /// them (ranked past the end of the stored list), so a stored order that
    /// omits providers — or names ones that no longer exist — degrades to a
    /// stable registration order. Disabled IDs are gone before this runs for
    /// `enabledProviders` because the caller filters first.
    private func ordered(_ input: [any AIProvider]) -> [any AIProvider] {
        guard !storedProviderOrder.isEmpty else { return input }
        let rank = Dictionary(
            storedProviderOrder.enumerated().map { ($1, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return input
            .enumerated()
            .sorted { lhs, rhs in
                let leftRank = rank[lhs.element.id] ?? (storedProviderOrder.count + lhs.offset)
                let rightRank = rank[rhs.element.id] ?? (storedProviderOrder.count + rhs.offset)
                if leftRank != rightRank { return leftRank < rightRank }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// Adds a provider dynamically
    public func addProvider(_ provider: any AIProvider) {
        providers.add(provider)
        loadHiddenQuotas(for: provider)
    }

    /// Removes a provider by ID
    public func removeProvider(id: String) {
        providers.remove(id: id)
    }

    /// Returns the lowest quota across all enabled providers
    public func lowestQuota() -> UsageQuota? {
        providers.enabled
            .compactMap { usage(of: $0)?.lowestQuota }
            .min()
    }

    /// Returns the selected quota for a provider from enabled provider snapshots.
    public func quota(providerId: String, quotaKey: String) -> UsageQuota? {
        providers.enabled
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
            guard let provider = enabledProviders.first(where: { $0.id == id }) else { return nil }
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
                return MenuBarProviderLabel(providerId: id, providerName: provider.name,
                                            label: MenuBarLabel(text: "—", status: .healthy))
            }
            return MenuBarProviderLabel(providerId: id, providerName: provider.name, label: label,
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
            ? (enabledProviders.first { $0.id == providerId }.flatMap { usage(of: $0) }?.quotas.first?.quotaType.quotaKey ?? "")
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

    /// Returns the overall status across enabled providers (worst status wins)
    public var overallStatus: QuotaStatus {
        providers.enabled
            .compactMap { usage(of: $0)?.overallStatus(under: statusPolicy) }
            .max() ?? .healthy
    }

    // MARK: - Selection

    /// The currently selected provider (from enabled providers)
    public var selectedProvider: (any AIProvider)? {
        providers.enabled.first { $0.id == selectedProviderId }
    }

    /// Status of the currently selected provider (for menu bar icon)
    public var selectedProviderStatus: QuotaStatus {
        selectedProvider.flatMap { usage(of: $0) }?.overallStatus(under: statusPolicy) ?? .healthy
    }

    /// Whether any provider is currently refreshing
    public var isRefreshing: Bool {
        providers.all.contains { $0.isSyncing }
    }

    /// Selects a provider by ID (must be enabled)
    public func selectProvider(id: String) {
        if providers.enabled.contains(where: { $0.id == id }) {
            selectedProviderId = id
        }
    }

    /// The popover's pills: one per product, its enabled logins inside —
    /// the tabs follow the persisted order (issue #141), not the
    /// registration order.
    public var tabs: [ProductTab] { ProductTab.tabs(of: enabledProviders) }

    /// The tab the selected login belongs to.
    public var selectedTab: ProductTab? { tabs.first { $0.contains(selectedProviderId) } }

    /// Selects the tab in the given 1-based slot, counted the way the popover
    /// lists them (⌘1 is the first pill), opening on its first login — the
    /// slots follow the persisted order (issue #141). A slot with no tab
    /// leaves the selection alone.
    public func selectProvider(atPosition position: Int) {
        let tabs = tabs
        guard tabs.indices.contains(position - 1), let first = tabs[position - 1].accounts.first else { return }
        selectedProviderId = first.id
    }

    /// Moves a provider up (negative offset) or down (positive offset) within
    /// the displayed order, clamped at the boundaries, and persists the new
    /// order. This is the one write path for reordering, so QuotaMonitor stays
    /// the single source of truth for provider order.
    public func moveProvider(id: String, by offset: Int) {
        guard offset != 0 else { return }
        let ids = ordered(providers.all).map(\.id)
        guard let index = ids.firstIndex(of: id) else { return }
        let newIndex = min(max(index + offset, 0), ids.count - 1)
        guard newIndex != index else { return }
        var reordered = ids
        reordered.remove(at: index)
        reordered.insert(id, at: newIndex)
        setProviderOrder(reordered)
    }

    /// Applies a full provider order and persists it through the settings
    /// repository (when one is wired). IDs that no longer exist in
    /// `providers.all` — extensions removed, a deleted Codex account — are
    /// dropped before anything is stored or persisted, so the saved order
    /// never accumulates dead ids. IDs missing from the list keep their
    /// registration position.
    public func setProviderOrder(_ order: [String]) {
        let live = Set(providers.all.map(\.id))
        let filtered = order.filter { live.contains($0) }
        storedProviderOrder = filtered
        settingsRepository?.setProviderOrder(filtered)
    }

    /// Sets a provider's enabled state.
    /// When disabling the currently selected provider, automatically switches
    /// to the first available enabled provider.
    public func setProviderEnabled(_ id: String, enabled: Bool) {
        guard let provider = providers.provider(id: id) else { return }
        provider.isEnabled = enabled
        if !enabled {
            selectFirstEnabledIfNeeded()
        }
    }

    /// Selects the first enabled provider if current selection is invalid.
    /// Called automatically during initialization and when providers are disabled.
    private func selectFirstEnabledIfNeeded() {
        if !providers.enabled.contains(where: { $0.id == selectedProviderId }),
           let firstEnabled = providers.enabled.first {
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
        return ids.compactMap { providers.provider(id: $0)?.backgroundRefreshFloor }
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
