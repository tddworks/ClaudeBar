import Quotas
import DataSources
import Providers
import Foundation
import Mockable

/// Domain protocol for alerting users about quota changes.
/// Implementations decide how to alert (notifications, sounds, etc.).
@Mockable
public protocol QuotaAlerter: Sendable {
    /// Requests permission to send alerts to the user.
    /// Returns true if permission was granted.
    func requestPermission() async -> Bool

    /// Called when a provider's quota status changes.
    /// Implementations should alert users if the status degraded.
    func alert(providerId: String, previousStatus: QuotaStatus, currentStatus: QuotaStatus) async
}
