import Foundation

/// HOW STRICT TO BE — the person's one judgement, for the whole app
/// (Settings → General → warn when a quota will run out before it resets).
/// Every surface reads a quota's status under it: the menu bar, the cards,
/// the pills, the Touch Bar, the notch, the status export and the notifications.
///
/// Depleted at 0 is absolute whatever the policy. Pace-aware reads the
/// quota's `Forecast`, which reads the one rule `SpendRate.runsOutBeforeReset`
/// that Pace reads too, so a quota never reads low beside *On track* or
/// *Room to spare*: it is critical when it runs out within
/// `criticalShareOfWindow` of its window, warning when it runs out later, and
/// healthy when it lasts until the reset, however little is left.
public enum StatusPolicy: Sendable, Equatable, Hashable {
    /// Warning under 50% left, whatever the pace.
    case absolute
    /// Warning exactly when, at its pace, the quota runs out before it
    /// resets, critical when that is soon; a quota without a rate yet falls
    /// back to absolute.
    case paceAware

    /// How soon a run-out is urgent under pace-aware, as a share of the
    /// window: 30 minutes of a 5-hour session, about 17 hours of a week.
    public static let criticalShareOfWindow: Double = 0.1

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
            guard let left = percentLeft, left > 0 else { return status }
            guard let forecast = forecast(at: now), let length = window?.length else { return status }
            switch forecast {
            case .lastsUntilReset:
                return .healthy
            case .runsOut(let runsOutIn, _):
                let soon = Duration.seconds(length * StatusPolicy.criticalShareOfWindow)
                return runsOutIn <= soon ? .critical : .warning
            }
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
