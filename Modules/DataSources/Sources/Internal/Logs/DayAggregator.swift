import Foundation
import Quotas

/// Records into days: each record on the local day its own time falls in,
/// priced, with working sessions split by `sessionGap`.
enum DayAggregator {
    /// One stat per day of `range`, every date present.
    /// - Parameter freeOn: the day an unpriced model costs nothing — the day
    ///   that holds now, when the route is local.
    static func days(_ records: [LogRecord], in range: DateRange, calendar: Calendar, sessionGap: Double?,
                     prices: PriceList?, freeOn: Date?) -> [DailyUsageStat] {
        let byDay = Dictionary(grouping: records.filter { range.contains($0.at, calendar: calendar) }) {
            calendar.startOfDay(for: $0.at)
        }
        return range.days(in: calendar).map { day in
            stat(byDay[day] ?? [], on: day, sessionGap: sessionGap, prices: prices, servedLocally: day == freeOn)
        }
    }

    static func stat(_ records: [LogRecord], on day: Date, sessionGap: Double?, prices: PriceList?,
                     servedLocally: Bool) -> DailyUsageStat {
        guard !records.isEmpty else { return .empty(for: day) }
        var cost: Decimal = 0
        var savings: Decimal = 0
        for record in records {
            if let own = record.cost {
                cost += own
            } else if let prices {
                cost += prices.cost(of: record, servedLocally: servedLocally)
                savings += prices.savings(of: record, servedLocally: servedLocally)
            }
        }
        let (workingTime, sessions) = sessionsAndTime(records, gap: sessionGap)
        return DailyUsageStat(
            date: day,
            totalCost: cost,
            totalTokens: records.reduce(0) { $0 + $1.tokens },
            workingTime: workingTime,
            sessionCount: sessions,
            inputTokens: records.reduce(0) { $0 + $1.input },
            outputTokens: records.reduce(0) { $0 + $1.output },
            cacheCreationTokens: records.reduce(0) { $0 + $1.cacheWrite },
            cacheReadTokens: records.reduce(0) { $0 + $1.cacheRead },
            cachedSavings: savings
        )
    }

    /// Working time from first to last record of each session, a pause longer
    /// than `gap` starting the next. Without a gap each record is a session
    /// and no working time is known.
    private static func sessionsAndTime(_ records: [LogRecord], gap: Double?) -> (TimeInterval, Int) {
        guard let gap else { return (0, records.count) }
        let times = records.map(\.at).sorted()
        var workingTime: TimeInterval = 0
        var sessions = 1
        var start = times[0]
        var last = times[0]
        for time in times.dropFirst() {
            if time.timeIntervalSince(last) > gap {
                workingTime += last.timeIntervalSince(start)
                start = time
                sessions += 1
            }
            last = time
        }
        workingTime += last.timeIntervalSince(start)
        return (workingTime, sessions)
    }
}
