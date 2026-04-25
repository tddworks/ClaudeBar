import Foundation
import Combine

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
public final class QuotaMonitor: ObservableObject, @unchecked Sendable {

    /// The providers repository (internal - access via delegation methods)
    private let providers: any AIProviderRepository

    /// Optional alerter for quota changes (e.g., system notifications)
    private let alerter: (any QuotaAlerter)?

    /// Clock for scheduling intervals (injectable for tests)
    private let clock: any Clock

    /// Previous status for change detection
    private var previousStatuses: [String: QuotaStatus] = [:]

    /// Current monitoring task
    private var monitoringTask: Task<Void, Never>?

    /// Combine subscriptions for forwarding provider changes
    private var providerCancellables: Set<AnyCancellable> = []

    /// Whether monitoring is active
    @Published public private(set) var isMonitoring: Bool = false

    /// The currently selected provider ID (for UI display)
    @Published public var selectedProviderId: String = "claude"

    // MARK: - Initialization

    /// Creates a QuotaMonitor with a provider repository.
    /// Automatically validates the selected provider on initialization.
    public init(
        providers: any AIProviderRepository,
        alerter: (any QuotaAlerter)? = nil,
        clock: any Clock
    ) {
        self.providers = providers
        self.alerter = alerter
        self.clock = clock
        selectFirstEnabledIfNeeded()
        forwardProviderChanges()
    }

    /// Subscribes to all providers' objectWillChange and forwards to our own.
    private func forwardProviderChanges() {
        for provider in providers.all {
            ObservableSubscriber.subscribe(
                to: provider,
                receiveOn: RunLoop.main,
                onChange: { [weak self] in
                    self?.objectWillChange.send()
                }
            ).store(in: &providerCancellables)
        }
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

    /// Refreshes a single provider
    private func refreshProvider(_ provider: any AIProvider) async {
        guard await provider.isAvailable() else {
            return
        }

        do {
            let snapshot = try await provider.refresh()
            await handleSnapshotUpdate(provider: provider, snapshot: snapshot)
        } catch {
            // Provider stores error in lastError - no need for external observer
        }
    }

    /// Handles snapshot update and alerts user if status changed
    private func handleSnapshotUpdate(provider: any AIProvider, snapshot: UsageSnapshot) async {
        let previousStatus = previousStatuses[provider.id] ?? .healthy
        let newStatus = snapshot.overallStatus

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
    public func refresh(providerId: String) async {
        guard let provider = providers.provider(id: providerId) else {
            return
        }
        await refreshProvider(provider)
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

    /// Returns all providers
    public var allProviders: [any AIProvider] {
        providers.all
    }

    /// Returns only enabled providers
    public var enabledProviders: [any AIProvider] {
        providers.enabled
    }

    /// Adds a provider dynamically
    public func addProvider(_ provider: any AIProvider) {
        providers.add(provider)
        ObservableSubscriber.subscribe(
            to: provider,
            receiveOn: RunLoop.main,
            onChange: { [weak self] in
                self?.objectWillChange.send()
            }
        ).store(in: &providerCancellables)
    }

    /// Removes a provider by ID
    public func removeProvider(id: String) {
        providers.remove(id: id)
    }

    /// Returns the lowest quota across all enabled providers
    public func lowestQuota() -> UsageQuota? {
        providers.enabled
            .compactMap(\.snapshot?.lowestQuota)
            .min()
    }

    /// Returns the overall status across enabled providers (worst status wins)
    public var overallStatus: QuotaStatus {
        providers.enabled
            .compactMap(\.snapshot?.overallStatus)
            .max() ?? .healthy
    }

    // MARK: - Selection

    /// The currently selected provider (from enabled providers)
    public var selectedProvider: (any AIProvider)? {
        providers.enabled.first { $0.id == selectedProviderId }
    }

    /// Status of the currently selected provider (for menu bar icon)
    public var selectedProviderStatus: QuotaStatus {
        selectedProvider?.snapshot?.overallStatus ?? .healthy
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

    /// Refreshes only the currently selected provider.
    public func refreshSelected() async {
        await refresh(providerId: selectedProviderId)
    }

    /// Starts continuous monitoring at the specified interval.
    /// Only refreshes the currently selected provider each cycle to minimize energy usage.
    /// Returns an AsyncStream of monitoring events.
    public func startMonitoring(interval: TimeInterval = 60) -> AsyncStream<MonitoringEvent> {
        // Stop any existing monitoring
        monitoringTask?.cancel()

        isMonitoring = true

        return AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    await self.refreshSelected()
                    continuation.yield(.refreshed)

                    do {
                        try await clock.sleep(for: interval)
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
