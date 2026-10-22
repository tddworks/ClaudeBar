import Foundation
import Quotas

/// Records into days: each record on the local day its own time falls in,
/// priced, with working sessions split by `sessionGap`. A day is the sum of
/// its lines — one per model, and, when the log names a working directory,
/// one per project (daily-usage design §1, quota-by-project design §3).
enum DayAggregator {
    /// Bumped when how days are summed changes. The log's fingerprint
    /// carries it, so kept days are summed again — a ledger is a cache, not
    /// a record.
    static let summingVersion = 2

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
        var tallies: [String: Tally] = [:]
        var projectTallies: [String: Tally] = [:]
        var namesAProject = false
        for record in records {
            let spent: Decimal?
            if let own = record.cost {
                cost += own
                spent = own
            } else if let prices {
                let priced = prices.cost(of: record, servedLocally: servedLocally)
                cost += priced
                savings += prices.savings(of: record, servedLocally: servedLocally)
                spent = priced
            } else {
                spent = nil
            }
            // A record without a declared model is one unnamed line; the
            // day's totals still hold it.
            let model = record.model ?? ""
            var tally = tallies[model] ?? Tally()
            tally.total += record.tokens
            tally.input += record.input
            tally.output += record.output
            tally.write += record.cacheWrite
            tally.read += record.cacheRead
            tally.cost += spent ?? 0
            tallies[model] = tally
            // …and to its project, named by the working directory's last
            // path component — the one place the naming happens, so a day is
            // never kept with a path.
            let project = record.project.map { ProjectUsageLine.name(of: $0) } ?? ""
            if !project.isEmpty { namesAProject = true }
            var projectTally = projectTallies[project] ?? Tally()
            projectTally.total += record.tokens
            projectTally.input += record.input
            projectTally.output += record.output
            projectTally.write += record.cacheWrite
            projectTally.read += record.cacheRead
            projectTally.cost += spent ?? 0
            projectTallies[project] = projectTally
        }
        // Named models in name order; the unnamed line last, so it reads as
        // what remains of the day.
        var lines = tallies
            .filter { !$0.key.isEmpty }
            .sorted { $0.key < $1.key }
            .map { key, tally in
                ModelUsageLine(model: key, inputTokens: tally.input, outputTokens: tally.output,
                               cacheCreationTokens: tally.write, cacheReadTokens: tally.read,
                               totalTokens: tally.total, cost: tally.cost)
            }
        if let unnamed = tallies[""] {
            lines.append(ModelUsageLine(model: "", inputTokens: unnamed.input, outputTokens: unnamed.output,
                                        cacheCreationTokens: unnamed.write, cacheReadTokens: unnamed.read,
                                        totalTokens: unnamed.total, cost: unnamed.cost))
        }
        let projects = Self.projectLines(projectTallies, namedAny: namesAProject)
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
            cachedSavings: savings,
            lines: lines,
            projects: projects
        )
    }

    /// A day's project split, one line per project, read from the tallies the
    /// records gathered: named lines in name order; on a day that names at
    /// least one project the records without a directory form the unnamed
    /// part last, so the parts add up to the day. A day whose records name no
    /// project carries no split at all.
    private static func projectLines(_ tallies: [String: Tally], namedAny: Bool) -> [ProjectUsageLine] {
        guard namedAny else { return [] }
        var lines = tallies
            .filter { !$0.key.isEmpty }
            .sorted { $0.key < $1.key }
            .map { project, tally in
                ProjectUsageLine(project: project, inputTokens: tally.input, outputTokens: tally.output,
                                 cacheCreationTokens: tally.write, cacheReadTokens: tally.read,
                                 totalTokens: tally.total, cost: tally.cost)
            }
        if let unnamed = tallies[""] {
            lines.append(ProjectUsageLine(project: "", inputTokens: unnamed.input, outputTokens: unnamed.output,
                                          cacheCreationTokens: unnamed.write, cacheReadTokens: unnamed.read,
                                          totalTokens: unnamed.total, cost: unnamed.cost))
        }
        return lines
    }

    /// One model's share of a day, gathered while the records pass.
    private struct Tally {
        var total = 0
        var input = 0
        var output = 0
        var write = 0
        var read = 0
        var cost: Decimal = 0
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
