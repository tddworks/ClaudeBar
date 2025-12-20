import Foundation

/// The main domain service that coordinates quota monitoring across AI providers.
/// This is the aggregate root for the monitoring bounded context.
public actor QuotaMonitor {
    /// All registered probes
    private let probes: [any UsageProbePort]

    /// Observer to notify of updates
    private let observer: any QuotaObserverPort

    /// Current snapshots by provider
    private var snapshots: [AIProvider: UsageSnapshot] = [:]

    /// Previous status for change detection
    private var previousStatuses: [AIProvider: QuotaStatus] = [:]

    // MARK: - Initialization

    public init(
        probes: [any UsageProbePort],
        observer: any QuotaObserverPort = NoOpQuotaObserver()
    ) {
        self.probes = probes
        self.observer = observer
    }

    // MARK: - Monitoring Operations

    /// Refreshes all registered providers and returns the updated snapshots.
    /// Providers are refreshed concurrently for efficiency.
    @discardableResult
    public func refreshAll() async throws -> [AIProvider: UsageSnapshot] {
        await withTaskGroup(of: (AIProvider, UsageSnapshot?).self) { group in
            for probe in probes {
                group.addTask {
                    await self.refreshProvider(probe)
                }
            }

            var results: [AIProvider: UsageSnapshot] = [:]
            for await (provider, snapshot) in group {
                if let snapshot {
                    results[provider] = snapshot
                }
            }

            // Update internal state
            for (provider, snapshot) in results {
                await self.updateSnapshot(provider: provider, snapshot: snapshot)
            }

            return results
        }
    }

    /// Refreshes a single provider
    private func refreshProvider(_ probe: any UsageProbePort) async -> (AIProvider, UsageSnapshot?) {
        let provider = probe.provider

        guard await probe.isAvailable() else {
            return (provider, nil)
        }

        do {
            let snapshot = try await probe.probe()
            return (provider, snapshot)
        } catch {
            await observer.onError(error, provider: provider)
            return (provider, nil)
        }
    }

    /// Updates the internal snapshot and notifies observers of changes
    private func updateSnapshot(provider: AIProvider, snapshot: UsageSnapshot) async {
        let previousStatus = previousStatuses[provider] ?? .healthy
        let newStatus = snapshot.overallStatus

        snapshots[provider] = snapshot
        previousStatuses[provider] = newStatus

        // Notify observer of snapshot update
        await observer.onSnapshotUpdated(snapshot)

        // Notify if status changed
        if previousStatus != newStatus {
            await observer.onStatusChanged(
                provider: provider,
                oldStatus: previousStatus,
                newStatus: newStatus
            )
        }
    }

    // MARK: - Queries

    /// Returns the current snapshot for a provider, if available
    public func snapshot(for provider: AIProvider) -> UsageSnapshot? {
        snapshots[provider]
    }

    /// Returns all current snapshots
    public func allSnapshots() -> [AIProvider: UsageSnapshot] {
        snapshots
    }

    /// Returns the lowest quota across all monitored providers
    public func lowestQuota() -> UsageQuota? {
        snapshots.values
            .compactMap(\.lowestQuota)
            .min()
    }

    /// Returns the overall status across all providers (worst status wins)
    public func overallStatus() -> QuotaStatus {
        snapshots.values
            .map(\.overallStatus)
            .max() ?? .healthy
    }
}
