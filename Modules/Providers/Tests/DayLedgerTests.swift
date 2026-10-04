import DataSources
import Foundation
import Providers
import Quotas
import Testing

/// The ledger: a day that has closed is summed once and kept, never read
/// from the logs again; the open days — today, and yesterday until an hour
/// past midnight — are read every time. A change to how the logs read
/// starts it over (TARGET_ARCHITECTURE §10.3).
@MainActor
@Suite
struct DayLedgerTests {
    final class Shelf: LedgerStore, @unchecked Sendable {
        var pages: [String: LedgerPage] = [:]
        func load(_ key: String) -> LedgerPage? { pages[key] }
        func save(_ page: LedgerPage, for key: String) { pages[key] = page }
    }

    private let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let calendar = Calendar.current
    private let shelf = Shelf()

    /// Today at `hour` o'clock.
    private func today(at hour: Double) -> Date {
        calendar.startOfDay(for: Date()).addingTimeInterval(hour * 3600)
    }

    private func history(now: Date, cost: String = "$.cost") -> UsageHistory {
        let definition = UsageLog.Definition(records: UsageLog.Records(
            files: "~/.acme/*.jsonl", at: "$.at", tokens: UsageLog.Tokens(total: "$.tokens"), cost: cost))
        let log = DataSources.makeUsageLog(definition, environment: { _ in nil }, homeDirectory: home,
                                           calendar: calendar, now: { now })
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

    @Test func `a closed day is kept, and not read from the logs again`() async throws {
        let now = today(at: 12)
        try log([(14, 0), (41, 1)], now: now)
        _ = await history(now: now).days(in: .last(2, endingOn: now))

        try forgetLogs()
        let days = await history(now: now).days(in: .last(2, endingOn: now))

        #expect(days.map(\.totalCost) == [41, 0])
    }

    @Test func `today is read every time`() async throws {
        let now = today(at: 12)
        try log([(14, 0)], now: now)
        let history = history(now: now)
        _ = await history.days(in: .last(2, endingOn: now))

        try log([(14, 0), (6, 0)], now: now)
        let days = await history.days(in: .last(2, endingOn: now))

        #expect(days.last?.totalCost == 20)
    }

    @Test func `yesterday stays open until an hour past midnight`() async throws {
        let now = today(at: 0.5)
        try log([(41, 1)], now: now)
        _ = await history(now: now).days(in: .last(2, endingOn: now))

        try forgetLogs()
        let days = await history(now: now).days(in: .last(2, endingOn: now))

        #expect(days.first?.totalCost == 0)
    }

    @Test func `thirty days are read once, then only the open ones`() async throws {
        let now = today(at: 12)
        try log((0..<30).map { (cost: $0 + 1, daysAgo: $0) }, now: now)
        let first = await history(now: now).days(in: .last(30, endingOn: now))

        try forgetLogs()
        let again = await history(now: now).days(in: .last(30, endingOn: now))

        #expect(first.count == 30)
        #expect(again.dropLast().map(\.totalCost) == first.dropLast().map(\.totalCost))
        #expect(again.last?.totalCost == 0)
        #expect(shelf.pages["acme"]?.days.count == 29)
    }

    @Test func `a day with nothing is kept as an empty day`() async throws {
        let now = today(at: 12)
        _ = await history(now: now).days(in: .last(3, endingOn: now))

        #expect(shelf.pages["acme"]?.days.count == 2)
    }

    @Test func `a change to how the logs read starts the ledger over`() async throws {
        let now = today(at: 12)
        try log([(41, 1)], now: now)
        _ = await history(now: now).days(in: .last(2, endingOn: now))

        try forgetLogs()
        let days = await history(now: now, cost: "$.price").days(in: .last(2, endingOn: now))

        #expect(days.first?.totalCost == 0)
    }

    @Test func `the cards read through the ledger too`() async throws {
        let now = today(at: 12)
        try log([(14, 0), (41, 1)], now: now)
        await history(now: now).read()

        try forgetLogs()
        let history = history(now: now)
        await history.read()

        #expect(history.report?.previous.totalCost == 41)
        #expect(history.report?.today.isEmpty == true)
    }
}
