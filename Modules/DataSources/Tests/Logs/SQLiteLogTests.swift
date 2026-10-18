import Foundation
import Quotas
import Testing
@testable import DataSources

/// A usage log read from one fixed read-only query of an app's own database —
/// the app's records without its CLI in between (`opencode`'s `db`
/// subcommand came and went; the database file stays, #566). Each row of the
/// answer is one record, its columns as the database wrote them.
@Suite
struct SQLiteLogTests {
    private let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let calendar = DataSources.calendar()
    private let now = Date()

    private var database: String { home.appendingPathComponent("acme/acme.db").path }

    /// Creates the fixture database with `rows` of usage and returns its path.
    private func makeDatabase(_ rows: String) throws -> String {
        try SQLiteFiles.make(at: URL(fileURLWithPath: database), rows)
        return database
    }

    private static let shapes = [UsageLog.Shape(at: "$.at", id: ["$.id"],
                                                tokens: UsageLog.Tokens(input: "$.used", output: "$.out", cacheRead: "$.cacheRead"),
                                                cost: "$.cost")]

    private static func records(_ call: SQLiteCall) -> UsageLog.Records {
        UsageLog.Records(sqlite: call, shapes: shapes)
    }

    private static func records(query: String) -> UsageLog.Records {
        records(SQLiteCall(path: "~/acme/acme.db", query: query))
    }

    private static let definition = UsageLog.Definition(records: records(query: "SELECT id, at, used, out, cacheRead, cost FROM live"), sessionGap: 1800)

    private func log(_ definition: UsageLog.Definition = Self.definition) -> UsageLog {
        DataSources.makeUsageLog(definition, platform: Platform.current, scripts: { _ in nil },
                                        environment: { _ in nil }, homeDirectory: home, now: { [now] in now })
    }

    private func epoch(daysAgo: Double = 0) -> Int { Int(now.addingTimeInterval(-daysAgo * 86_400).timeIntervalSince1970) }

    private func row(id: String, at: Int, input: Int, output: Int, cost: Double) -> String {
        "INSERT INTO live VALUES ('\(id)', \(at), \(input), \(output), 0, \(cost));"
    }

    @Test func `should read one record a row of the database's answer`() async throws {
        try makeDatabase("CREATE TABLE live(id TEXT, at INTEGER, used INTEGER, out INTEGER, cacheRead INTEGER, cost REAL); "
                         + row(id: "a", at: epoch(), input: 1000, output: 500, cost: 0.01))
        let days = await log().days(last: 1)
        #expect(days[0].totalTokens == 1500)
        #expect(days[0].totalCost == Decimal(string: "0.01"))
    }

    @Test func `should show every day empty when the database has no such table, or is not there`() async throws {
        try makeDatabase("CREATE TABLE other(id TEXT);")
        #expect(await log().days(last: 1)[0].isEmpty)
        try FileManager.default.removeItem(atPath: database)
        #expect(await log().days(last: 1)[0].isEmpty)
    }

    @Test func `should read a count the database wrote as text`() async throws {
        try makeDatabase("CREATE TABLE live(id TEXT, at TEXT, used TEXT, out TEXT, cacheRead TEXT, cost TEXT); "
                         + "INSERT INTO live VALUES ('a', '\(epoch())', '1000', '500', '0', '0.01');")
        let days = await log().days(last: 1)
        #expect(days[0].totalTokens == 1500)
        #expect(days[0].totalCost == Decimal(string: "0.01"))
    }

    @Test func `should read every row of the database, however many records it holds`() async throws {
        // A fetch's answer stops at 1 000 rows, to spare a script; a log's
        // records go to the aggregator, and a day cut short is a wrong day.
        let rows = (0..<1_500).map { "('m\($0)', \(epoch()), 1, 0, 0, 0)" }.joined(separator: ", ")
        try makeDatabase("CREATE TABLE live(id TEXT, at INTEGER, used INTEGER, out INTEGER, cacheRead INTEGER, cost REAL); "
                         + "INSERT INTO live VALUES \(rows);")
        #expect(await log().days(last: 1)[0].totalTokens == 1_500)
    }

    // MARK: - A store whose tables moved: the first query it can answer

    /// An app that kept records in `archive`, then `live`; an upgraded store
    /// holds both, and its first query reads both places.
    private static let moved = UsageLog.Definition(records: records(SQLiteCall(path: "~/acme/acme.db", queries: [
        SQLiteCall.Query(requires: ["archive", "live"], query: "SELECT id, at, used, out, cacheRead, cost FROM live UNION ALL SELECT id, at, used, out, cacheRead, cost FROM archive"),
        SQLiteCall.Query(requires: ["live"], query: "SELECT id, at, used, out, cacheRead, cost FROM live"),
        SQLiteCall.Query(requires: ["archive"], query: "SELECT id, at, used, out, cacheRead, cost FROM archive"),
    ])), sessionGap: 1800)

    private static let table = "(id TEXT, at INTEGER, used INTEGER, out INTEGER, cacheRead INTEGER, cost REAL)"

    @Test func `should read the past and the present of a store that moved its records as one log`() async throws {
        try makeDatabase("CREATE TABLE live\(Self.table); CREATE TABLE archive\(Self.table); "
                         + "INSERT INTO live VALUES ('a', \(epoch()), 1000, 500, 0, 0); "
                         + "INSERT INTO archive VALUES ('b', \(epoch(daysAgo: 1)), 2000, 1000, 0, 0);")
        let days = await log(Self.moved).days(last: 2)
        #expect(days[1].totalTokens == 1500) // today, from `live`
        #expect(days[0].totalTokens == 3000) // yesterday, from `archive`
    }

    @Test(arguments: ["live", "archive"])
    func `should read a store that only one of its layouts wrote`(_ table: String) async throws {
        try makeDatabase("CREATE TABLE \(table)\(Self.table); INSERT INTO \(table) VALUES ('a', \(epoch()), 1000, 500, 0, 0);")
        #expect(await log(Self.moved).days(last: 1)[0].totalTokens == 1500)
    }

    @Test func `should count a record both places hold once`() async throws {
        try makeDatabase("CREATE TABLE live\(Self.table); CREATE TABLE archive\(Self.table); "
                         + "INSERT INTO live VALUES ('a', \(epoch()), 1000, 500, 0, 0); "
                         + "INSERT INTO archive VALUES ('a', \(epoch()), 1000, 500, 0, 0);")
        #expect(await log(Self.moved).days(last: 1)[0].totalTokens == 1500)
    }

    @Test func `should show every day empty when the store has none of the tables its queries read`() async throws {
        try makeDatabase("CREATE TABLE other(id TEXT);")
        #expect(await log(Self.moved).days(last: 1)[0].isEmpty)
    }

    // MARK: - The definition

    @Test func `should keep a database log when written out and read back`() throws {
        for definition in [Self.definition, Self.moved] {
            let again = try JSONDecoder().decode(UsageLog.Definition.self, from: JSONEncoder().encode(definition))
            #expect(again == definition)
        }
        #expect(Self.definition.records.source == .sqlite(SQLiteCall(path: "~/acme/acme.db", query: "SELECT id, at, used, out, cacheRead, cost FROM live")))
    }

    @Test func `should fingerprint two queries apart, so days kept under one are not reused for the other`() throws {
        let other = UsageLog.Definition(records: Self.records(query: "SELECT id, at, used, out, cacheRead, cost FROM other"), sessionGap: 1800)
        #expect(log(other).fingerprint != log().fingerprint)
        #expect(log(Self.moved).fingerprint != log().fingerprint)
    }
}
