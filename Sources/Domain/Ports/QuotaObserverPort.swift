import Foundation
import Mockable

/// Port for observing quota changes and publishing updates.
/// This allows the domain to notify interested parties (like UI) without coupling to them.
@Mockable
public protocol QuotaObserverPort: Sendable {
    /// Called when a new usage snapshot is available
    func onSnapshotUpdated(_ snapshot: UsageSnapshot) async

    /// Called when a quota status changes (e.g., from healthy to warning)
    func onStatusChanged(provider: AIProvider, oldStatus: QuotaStatus, newStatus: QuotaStatus) async

    /// Called when an error occurs during monitoring
    func onError(_ error: Error, provider: AIProvider) async
}

/// A no-op observer for when no observer is registered
public struct NoOpQuotaObserver: QuotaObserverPort {
    public init() {}

    public func onSnapshotUpdated(_ snapshot: UsageSnapshot) async {}
    public func onStatusChanged(provider: AIProvider, oldStatus: QuotaStatus, newStatus: QuotaStatus) async {}
    public func onError(_ error: Error, provider: AIProvider) async {}
}
