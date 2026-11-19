import DataSources
import Foundation
import Providers
import Quotas
import Testing

/// The ledger: a day that has closed is summed once and kept, never read
/// from the logs again; the open days — today, and yesterday until an hour
/// past midnight — are read every time. A change to how the logs read
/// starts it over (daily-usage design §3).
@MainActor
@Suite
struct DayLedgerTests {
    final class Shelf: LedgerStore, @unchecked Sendable {
        var pages: [String: LedgerPage] = [:]
        func load(_ key: String) -> LedgerPage? { pages[key] }
        func save(_ page: LedgerPage, for key: String) { pages[key] = page }
    }

    private let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let calendar = DataSources.calendar()
    private let shelf = Shelf()

    /// Today at `hour` o'clock.
    private func today(at hour: Double) -> Date {
        calendar.startOfDay(for: Date()).addingTimeInterval(hour * 3600)
    }

    private func history(now: Date, cost: String = "$.cost", model: String? = nil) -> UsageHistory {
        let definition = UsageLog.Definition(records: UsageLog.Records(
            files: "~/.acme/*.jsonl", at: "$.at", model: model, tokens: UsageLog.Tokens(total: "$.tokens"), cost: cost))
        let log = DataSources.makeUsageLog(definition, environment: { _ in nil }, homeDirectory: home, now: { now })
        return UsageHistory(log: log, ledger: DayLedger(store: shelf, key: "acme"))
    }

    /// One record per entry, `daysAgo` days before `now`, at noon.
    private func log(_ entries: [(cost: Int, daysAgo: Int)], now: Date) throws {
        let dir = home.appendingPathComponent(".acme")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let lines = entries.map { entry -> String in
            let day = calendar.date(byAdding: .day, value: -entry.daysAgo, to: calendar.startOfDay(for: now))!
            return #"{"at":\#(day.addingTimeInterval(43_200).timeIntervalSince1970),"tokens":1000,"cost":\#(entry.cost)}"#
        }
        try lines.joined(separator: "\n").write(to: dir.appendingPathComponent("log.jsonl"), atomically: true, encoding: .utf8)
    }

    private func forgetLogs() throws {
        try FileManager.default.removeItem(at: home.appendingPathComponent(".acme"))
    }

    @Test func `should keep a closed day's usage after the logs are gone`() async throws {
        let now = today(at: 12)
        try log([(14, 0), (41, 1)], now: now)
        _ = await history(now: now).days(in: .last(2, endingOn: now, calendar: calendar))

        try forgetLogs()
        let days = await history(now: now).days(in: .last(2, endingOn: now, calendar: calendar))

        #expect(days.stats.map(\.totalCost) == [41, 0])
    }

    @Test func `should show today's latest usage every time it is read`() async throws {
        let now = today(at: 12)
        try log([(14, 0)], now: now)
        let history = history(now: now)
        _ = await history.days(in: .last(2, endingOn: now, calendar: calendar))

        try log([(14, 0), (6, 0)], now: now)
        let days = await history.days(in: .last(2, endingOn: now, calendar: calendar))

        #expect(days.stats.last?.totalCost == 20)
    }

    @Test func `should keep reading yesterday from the logs until an hour past midnight`() async throws {
        let now = today(at: 0.5)
        try log([(41, 1)], now: now)
        _ = await history(now: now).days(in: .last(2, endingOn: now, calendar: calendar))

        try forgetLogs()
        let days = await history(now: now).days(in: .last(2, endingOn: now, calendar: calendar))

        #expect(days.stats.first?.totalCost == 0)
    }

    @Test func `should keep thirty closed days from one read and read only today again`() async throws {
        let now = today(at: 12)
        try log((0..<30).map { (cost: $0 + 1, daysAgo: $0) }, now: now)
        let first = await history(now: now).days(in: .last(30, endingOn: now, calendar: calendar))

        try forgetLogs()
        let again = await history(now: now).days(in: .last(30, endingOn: now, calendar: calendar))

        #expect(first.stats.count == 30)
        #expect(again.stats.dropLast().map(\.totalCost) == first.stats.dropLast().map(\.totalCost))
        #expect(again.stats.last?.totalCost == 0)
        #expect(shelf.pages["acme"]?.days.count == 29)
    }

    @Test func `should keep a closed day with no usage as an empty day`() async throws {
        let now = today(at: 12)
        _ = await history(now: now).days(in: .last(3, endingOn: now, calendar: calendar))

        #expect(shelf.pages["acme"]?.days.count == 2)
    }

    @Test func `should read the logs again from scratch when how they are read changes`() async throws {
        let now = today(at: 12)
        try log([(41, 1)], now: now)
        _ = await history(now: now).days(in: .last(2, endingOn: now, calendar: calendar))

        try forgetLogs()
        let days = await history(now: now, cost: "$.price").days(in: .last(2, endingOn: now, calendar: calendar))

        #expect(days.stats.first?.totalCost == 0)
    }

    @Test func `should show yesterday's kept usage on the cards after the logs are gone`() async throws {
        let now = today(at: 12)
        try log([(14, 0), (41, 1)], now: now)
        await history(now: now).read()

        try forgetLogs()
        let history = history(now: now)
        await history.read()

        #expect(history.report?.previous.totalCost == 41)
        #expect(history.report?.today.isEmpty == true)
    }

    /// One day, two models with their own costs, logged directly.
    private func logTwoModels(_ now: Date) throws {
        let dir = home.appendingPathComponent(".acme")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let day = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
        let lines = [
            #"{"at":\#(day.addingTimeInterval(43_200).timeIntervalSince1970),"model":"m-large","input":1000,"output":200,"cost":1.5}"#,
            #"{"at":\#(day.addingTimeInterval(43_600).timeIntervalSince1970),"model":"m-small","input":100,"output":200,"cost":0.25}"#,
        ]
        try lines.joined(separator: "\n").write(to: dir.appendingPathComponent("log.jsonl"), atomically: true, encoding: .utf8)
    }

    /// A log that names its models and their input and output.
    private func modelHistory(now: Date) -> UsageHistory {
        let definition = UsageLog.Definition(records: UsageLog.Records(
            files: "~/.acme/*.jsonl", at: "$.at", model: "$.model",
            tokens: UsageLog.Tokens(input: "$.input", output: "$.output"), cost: "$.cost"))
        let log = DataSources.makeUsageLog(definition, environment: { _ in nil }, homeDirectory: home, now: { now })
        return UsageHistory(log: log, ledger: DayLedger(store: shelf, key: "acme"))
    }

    @Test func `should keep a closed day's per-model lines after the logs are gone`() async throws {
        let now = today(at: 12)
        try logTwoModels(now)
        _ = await modelHistory(now: now).days(in: .last(2, endingOn: now, calendar: calendar))

        try forgetLogs()
        let days = await modelHistory(now: now).days(in: .last(2, endingOn: now, calendar: calendar))

        #expect(days.stats.first?.lines == [
            ModelUsageLine(model: "m-large", inputTokens: 1000, outputTokens: 200, totalTokens: 1200, cost: 1.5),
            ModelUsageLine(model: "m-small", inputTokens: 100, outputTokens: 200, totalTokens: 300, cost: 0.25),
        ])
    }

    // MARK: - The hours of a day

    @Test func `should keep the hours a closed day was spent in after the logs are gone`() async throws {
        let now = today(at: 12)
        try log([(41, 1)], now: now)
        _ = await history(now: now).days(in: .last(2, endingOn: now, calendar: calendar))

        try forgetLogs()
        let days = await history(now: now).days(in: .last(2, endingOn: now, calendar: calendar))

        #expect(days.stats.first?.hours.lines?.map(\.spend.cost) == [41])
    }

    /// The days on the shelf, as they were kept before days were split by hour.
    private func forgetHours() {
        guard let page = shelf.pages["acme"] else { return }
        shelf.pages["acme"] = LedgerPage(fingerprint: page.fingerprint, days: page.days.mapValues { $0.with(hours: .notRead) })
    }

    /// The day kept for `daysAgo` days before `now`.
    private func kept(_ daysAgo: Int, now: Date) -> DailyUsageStat? {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
        return shelf.pages["acme"]?.days.values.first { $0.date == day }
    }

    /// A day kept by an earlier version has no hours; its logs still do.
    @Test func `should read a day kept before hours again for its hours`() async throws {
        let now = today(at: 12)
        try log([(41, 1)], now: now)
        _ = await history(now: now).days(in: .last(2, endingOn: now, calendar: calendar))
        forgetHours()

        let days = await history(now: now).days(in: .last(2, endingOn: now, calendar: calendar))

        #expect(days.stats.first?.totalCost == 41)
        #expect(days.stats.first?.knowsHours == true)
        #expect(kept(1, now: now)?.knowsHours == true)
    }

    /// A tool cleared its logs: the kept day is all there is, and it stays.
    @Test func `should keep a day kept before hours when its logs are gone, without its hours`() async throws {
        let now = today(at: 12)
        try log([(41, 1)], now: now)
        _ = await history(now: now).days(in: .last(2, endingOn: now, calendar: calendar))
        forgetHours()
        try forgetLogs()

        let days = await history(now: now).days(in: .last(2, endingOn: now, calendar: calendar))

        #expect(days.stats.first?.totalCost == 41)
        #expect(days.stats.first?.knowsHours == false)
        // Asked once: the kept day is marked, never asked of the logs again.
        #expect(kept(1, now: now)?.hours == .notKept)
    }

    /// The thirty days are read first and mark yesterday; the year then
    /// starts at an older day still to read and reads through yesterday
    /// again. Its logs are gone, and it must not go with them.
    @Test func `should keep a day already marked when a longer range is read again from an older day`() async throws {
        let now = today(at: 12)
        try log([(41, 1), (7, 5)], now: now)
        _ = await history(now: now).days(in: .last(6, endingOn: now, calendar: calendar))
        forgetHours()
        try forgetLogs()
        _ = await history(now: now).days(in: .last(2, endingOn: now, calendar: calendar))
        #expect(kept(1, now: now)?.hours == .notKept)
        #expect(kept(5, now: now)?.needsHoursRead == true)

        let days = await history(now: now).days(in: .last(6, endingOn: now, calendar: calendar))

        #expect(days.stats.map(\.totalCost) == [7, 0, 0, 0, 41, 0])
        #expect(kept(1, now: now)?.totalCost == 41)
        #expect(kept(5, now: now)?.hours == .notKept)
    }

    /// The same re-read never takes a day that knows its hours either.
    @Test func `should keep a day that knows its hours when a longer range is read again and its logs are gone`() async throws {
        let now = today(at: 12)
        try log([(41, 1), (7, 5)], now: now)
        _ = await history(now: now).days(in: .last(6, endingOn: now, calendar: calendar))
        let yesterday = try #require(kept(1, now: now))
        let older = try #require(kept(5, now: now))
        shelf.pages["acme"] = shelf.pages["acme"].map { page in
            LedgerPage(fingerprint: page.fingerprint,
                       days: page.days.mapValues { $0.date == older.date ? $0.with(hours: .notRead) : $0 })
        }
        try forgetLogs()

        let days = await history(now: now).days(in: .last(6, endingOn: now, calendar: calendar))

        #expect(days.stats[4] == yesterday)
        #expect(kept(1, now: now) == yesterday)
    }
}
