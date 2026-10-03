import Foundation
import Mockable

/// Settings repository for user-configured quota alert thresholds (issue #68).
///
/// Standalone protocol rather than a `ProviderSettingsRepository` sub-protocol:
/// alerting is a destination, not a provider — same split as
/// `HookSettingsRepository` and `NotifySettingsRepository`. Persisted by
/// `JSONSettingsRepository` alongside the other settings.
@Mockable
public protocol QuotaAlertSettingsRepository: Sendable {
    /// The remaining-percentage thresholds a breach of which fires a
    /// notification. Empty by default: the fixed status-level alerts
    /// (warning/critical/depleted) work regardless.
    func alertThresholds() -> [QuotaAlertThreshold]

    /// Replaces the configured thresholds.
    func setAlertThresholds(_ thresholds: [QuotaAlertThreshold])
}
