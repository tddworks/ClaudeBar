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

    /// Called when a provider's remaining percentage crosses below a
    /// user-configured threshold (issue #68). The crossing decision — including
    /// fire-once-per-crossing hysteresis — belongs to the caller; implementations
    /// only deliver the alert.
    func alertThresholdCrossed(
        providerId: String,
        percentRemaining: Double,
        threshold: QuotaAlertThreshold
    ) async
}
