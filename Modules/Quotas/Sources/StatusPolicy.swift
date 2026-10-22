import Foundation

/// HOW STRICT TO BE — the person's one judgement, for the whole app
/// (Settings → General → warn when a quota will run out before it resets).
/// Every surface reads a quota's status under it: the menu bar, the cards,
/// the pills, the Touch Bar, the notch, the status export and the notifications.
///
/// Depleted at 0 and critical under 20% are absolute whatever the policy.
/// Pace-aware decides warning vs healthy from 20% up by the one rule
/// `SpendRate.runsOutBeforeReset`, the rule Pace and the forecast read, so a
/// quota never reads low beside *On track*.
public enum StatusPolicy: Sendable, Equatable, Hashable {
    /// Warning under 50% left, whatever the pace.
    case absolute
    /// Warning exactly when, at its pace, the quota runs out before it
    /// resets; a quota without a rate yet falls back to absolute.
    case paceAware

    /// The policy the person's warning switch describes.
    public static func from(burnRateWarningEnabled: Bool) -> StatusPolicy {
        burnRateWarningEnabled ? .paceAware : .absolute
    }
}

extension UsageQuota {
    /// This quota's status under the person's policy.
    public func status(under policy: StatusPolicy) -> QuotaStatus {
        status(under: policy, at: Date())
    }

    /// This quota's status under the person's policy, as of `now`.
    public func status(under policy: StatusPolicy, at now: Date) -> QuotaStatus {
        switch policy {
        case .absolute:
            return status
        case .paceAware:
            // The same share left and the same rate Pace and the forecast read.
            guard let rate = rate(at: now), let left = percentLeft else { return status }
            let absolute = QuotaStatus.from(percentRemaining: left)
            guard absolute < .critical else { return absolute }
            return rate.runsOutBeforeReset ? .warning : .healthy
        }
    }
}

extension UsageSnapshot {
    /// The worst quota's status under the person's policy.
    public func overallStatus(under policy: StatusPolicy) -> QuotaStatus {
        overallStatus(under: policy, at: Date())
    }

    /// The worst quota's status under the person's policy, as of `now`.
    public func overallStatus(under policy: StatusPolicy, at now: Date) -> QuotaStatus {
        quotas.map { $0.status(under: policy, at: now) }.max() ?? .healthy
    }
}
