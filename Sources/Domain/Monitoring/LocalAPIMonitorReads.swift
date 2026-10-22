import Foundation
import Mockable
import Providers
import Quotas

/// THE MONITOR'S READS, as the local API asks them — the seam between the
/// wire and the Monitor. `MonitorLocalAPIReading` answers every route from
/// these reads alone; `QuotaMonitor` is the one who answers them. The API
/// holds no number of its own and never refreshes: it reads what the screens
/// read, and only what is asked of it.
@Mockable
@MainActor
public protocol LocalAPIMonitorReads: Sendable {
    /// The worst status across the watched logins, under the person's policy.
    var overallStatus: QuotaStatus { get }

    /// The watched logins, in the person's order.
    var lineup: [Account] { get }

    /// The product a login belongs to, when one stands behind it.
    func product(of login: Account) -> Provider?

    /// What the login last said.
    func usage(of login: Account) -> UsageSnapshot?

    /// The name the person sees for the login.
    func lineupName(of login: Account) -> String

    /// The login's own status under the person's policy.
    func status(of login: Account) -> QuotaStatus?

    /// The login's day-by-day usage over a range — read on the ask, never in
    /// the background. A login with no history has no days.
    func days(of login: Account, in range: DateRange) async -> Quotas.Days?
}

extension QuotaMonitor: LocalAPIMonitorReads {
    public func days(of login: Account, in range: DateRange) async -> Quotas.Days? {
        guard let history = login.usageHistory else { return nil }
        return await history.days(in: range)
    }
}
