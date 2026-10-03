import DataSources
import Foundation
import Observation
import Quotas

/// *TODAY'S USAGE* — what one login used, day by day, read from its tool's
/// own logs on this Mac. Not a meter: nothing is left or judged, and the
/// monitor never refreshes it; it is read when the popover opens. The login
/// owns it, as `account.usageHistory` (CANONICAL §2.1); how the days are
/// extracted is its provider's `usageHistory`, run as a `UsageLog`.
@MainActor
@Observable
public final class UsageHistory {
    /// Today's and yesterday's usage, once read and when either holds any.
    public private(set) var report: DailyUsageReport?

    private enum Source {
        case log(UsageLog)
        /// - Note: Interim — Mistral's analyzer until its definition says
        ///   how to read its logs (TARGET §10.7, UH3).
        case analyzer(any DailyUsageAnalyzing)
    }

    private let source: Source

    public init(log: UsageLog) {
        source = .log(log)
    }

    public init(analyzer: any DailyUsageAnalyzing) {
        source = .analyzer(analyzer)
    }

    /// One day per date of `range`, every date present.
    public func days(in range: DateRange) async -> [DailyUsageStat] {
        switch source {
        case .log(let log): await log.days(in: range)
        case .analyzer: []
        }
    }

    /// Reads the logs again. A day with nothing on either side is kept as
    /// none; logs that can't be read leave the last report.
    public func read() async {
        let report: DailyUsageReport
        switch source {
        case .log(let log):
            let days = await log.days(last: 2)
            guard days.count == 2 else { return }
            report = DailyUsageReport(today: days[1], previous: days[0])
        case .analyzer(let analyzer):
            guard let read = try? await analyzer.analyzeToday() else { return }
            report = read
        }
        self.report = report.today.isEmpty && report.previous.isEmpty ? nil : report
    }
}
