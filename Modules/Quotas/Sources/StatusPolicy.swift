import Foundation

/// HOW STRICT TO BE — the person's one judgement, for the whole app
/// (Settings → General → burn-rate warning). Every surface reads a quota's
/// status under it: the menu bar, the cards, the pills, the Touch Bar, the
/// notch, the status export and the notifications.
///
/// Depleted at 0 and critical under 20% are absolute whatever the policy;
/// pace-aware only decides warning vs healthy between 20% and 50% left.
public enum StatusPolicy: Sendable, Equatable, Hashable {
    /// Warning under 50% left, whatever the pace.
    case absolute
    /// Warning only while burning faster than `burnRateThreshold` times the
    /// sustainable pace; a quota without a window falls back to absolute.
    case paceAware(burnRateThreshold: Double)

    /// The policy the burn-rate settings describe.
    public static func from(burnRateWarningEnabled: Bool, burnRateThreshold: Double) -> StatusPolicy {
        burnRateWarningEnabled ? .paceAware(burnRateThreshold: burnRateThreshold) : .absolute
    }
}

extension UsageQuota {
    /// This quota's status under the person's policy.
    public func status(under policy: StatusPolicy) -> QuotaStatus {
        switch policy {
        case .absolute: status
        case .paceAware(let threshold): paceAwareStatus(burnRateThreshold: threshold)
        }
    }
}

extension UsageSnapshot {
    /// The worst quota's status under the person's policy.
    public func overallStatus(under policy: StatusPolicy) -> QuotaStatus {
        quotas.map { $0.status(under: policy) }.max() ?? .healthy
    }
}
