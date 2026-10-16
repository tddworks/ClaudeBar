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
        let folder = home.appendingPathComponent("acme")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [database, rows]
        try process.run()
        process.waitUntilExit()
        return database
    }

    private static let shapes = [UsageLog.Shape(at: "$.at", id: ["$.id"],
                                                tokens: UsageLog.Tokens(input: "$.used", output: "$.out", cacheRead: "$.cacheRead"),
                                                cost: "$.cost")]

    private static func records(query: String, also query2: String? = nil) -> UsageLog.Records {
        UsageLog.Records(sqlite: SQLiteCall(path: "~/acme/acme.db", query: query),
                         also: query2.map { .sqlite(SQLiteCall(path: "~/acme/acme.db", query: $0)) },
                         shapes: shapes)
    }

    private static let definition = UsageLog.Definition(records: records(query: "SELECT id, at, used, out, cacheRead, cost FROM live"), sessionGap: 1800)

    private func log(_ definition: UsageLog.Definition = Self.definition, sqlite: Bool = true) -> UsageLog {
        var platform = Platform.current
        if !sqlite { platform.sqlite = nil }
        return DataSources.makeUsageLog(definition, platform: platform, scripts: { _ in nil },
                                        environment: { _ in nil }, homeDirectory: home, now: { [now] in now })
    }

    private func epoch(daysAgo: Double = 0) -> Int { Int(now.addingTimeInterval(-daysAgo * 86_400).timeIntervalSince1970) }

    private func row(id: String, at: Int, input: Int, output: Int, cost: Double) -> String {
        "INSERT INTO live VALUES ('\(id)', \(at), \(input), \(output), 0, \(cost));"
    }

    @Test(.needsSQLite) func `should read one record a row of the database's answer`() async throws {
        try makeDatabase("CREATE TABLE live(id TEXT, at INTEGER, used INTEGER, out INTEGER, cacheRead INTEGER, cost REAL); "
                         + row(id: "a", at: epoch(), input: 1000, output: 500, cost: 0.01))
        let days = await log().days(last: 1)
        #expect(days[0].totalTokens == 1500)
        #expect(days[0].totalCost == Decimal(string: "0.01"))
    }

    @Test(.needsSQLite) func `should show every day empty when the database has no such table, or is not there`() async throws {
        try makeDatabase("CREATE TABLE other(id TEXT);")
        #expect(await log().days(last: 1)[0].isEmpty)
        try FileManager.default.removeItem(atPath: database)
        #expect(await log().days(last: 1)[0].isEmpty)
    }

    @Test(.needsSQLite) func `should read a count the database wrote as text`() async throws {
        try makeDatabase("CREATE TABLE live(id TEXT, at TEXT, used TEXT, out TEXT, cacheRead TEXT, cost TEXT); "
                         + "INSERT INTO live VALUES ('a', '\(epoch())', '1000', '500', '0', '0.01');")
        let days = await log().days(last: 1)
        #expect(days[0].totalTokens == 1500)
        #expect(days[0].totalCost == Decimal(string: "0.01"))
    }

    @Test func `should show every day empty on a platform with no SQLite`() async {
        #expect(await log(sqlite: false).days(last: 1)[0].isEmpty)
    }

    // MARK: - `also`: the second place the database writes its records

    @Test(.needsSQLite) func `should read the records of both places the database writes them, each once`() async throws {
        try makeDatabase("CREATE TABLE live(id TEXT, at INTEGER, used INTEGER, out INTEGER, cacheRead INTEGER, cost REAL); "
                         + "CREATE TABLE archive(id TEXT, at INTEGER, used INTEGER, out INTEGER, cacheRead INTEGER, cost REAL); "
                         + row(id: "a", at: epoch(), input: 1000, output: 500, cost: 0)
                         + "INSERT INTO archive VALUES ('b', \(epoch(daysAgo: 1)), 2000, 1000, 0, 0);")
        let definition = UsageLog.Definition(
            records: Self.records(query: "SELECT id, at, used, out, cacheRead, cost FROM live",
                                  also: "SELECT id, at, used, out, cacheRead, cost FROM archive"),
            sessionGap: 1800)
        let days = await log(definition).days(last: 2)
        #expect(days[1].totalTokens == 1500) // today, from `live`
        #expect(days[0].totalTokens == 3000) // yesterday, from `archive`
    }

    @Test(.needsSQLite) func `should read what answers when one place the database writes is missing`() async throws {
        try makeDatabase("CREATE TABLE live(id TEXT, at INTEGER, used INTEGER, out INTEGER, cacheRead INTEGER, cost REAL); "
                         + row(id: "a", at: epoch(), input: 1000, output: 500, cost: 0))
        let definition = UsageLog.Definition(
            records: Self.records(query: "SELECT id, at, used, out, cacheRead, cost FROM live",
                                  also: "SELECT id, at, used, out, cacheRead, cost FROM missing"),
            sessionGap: 1800)
        #expect(await log(definition).days(last: 1)[0].totalTokens == 1500)
    }

    @Test(.needsSQLite) func `should count a record both places wrote once`() async throws {
        try makeDatabase("CREATE TABLE live(id TEXT, at INTEGER, used INTEGER, out INTEGER, cacheRead INTEGER, cost REAL); "
                         + "CREATE TABLE archive(id TEXT, at INTEGER, used INTEGER, out INTEGER, cacheRead INTEGER, cost REAL); "
                         + "INSERT INTO live VALUES ('a', \(epoch()), 1000, 500, 0, 0); "
                         + "INSERT INTO archive VALUES ('a', \(epoch()), 1000, 500, 0, 0);")
        let definition = UsageLog.Definition(
            records: Self.records(query: "SELECT id, at, used, out, cacheRead, cost FROM live",
                                  also: "SELECT id, at, used, out, cacheRead, cost FROM archive"),
            sessionGap: 1800)
        #expect(await log(definition).days(last: 1)[0].totalTokens == 1500)
    }

    // MARK: - The definition

    @Test(.needsSQLite) func `should keep a database log when written out and read back`() throws {
        let again = try JSONDecoder().decode(UsageLog.Definition.self, from: JSONEncoder().encode(Self.definition))
        #expect(again == Self.definition)
        #expect(again.records.source == .sqlite(SQLiteCall(path: "~/acme/acme.db", query: "SELECT id, at, used, out, cacheRead, cost FROM live")))
    }

    @Test(.needsSQLite) func `should fingerprint two queries apart, so days kept under one are not reused for the other`() throws {
        let other = UsageLog.Definition(records: Self.records(query: "SELECT id, at, used, out, cacheRead, cost FROM other"), sessionGap: 1800)
        #expect(log(other).fingerprint != log().fingerprint)
        let also = UsageLog.Definition(records: Self.records(query: "SELECT id, at, used, out, cacheRead, cost FROM live",
                                                             also: "SELECT id, at, used, out, cacheRead, cost FROM archive"), sessionGap: 1800)
        #expect(log(also).fingerprint != log().fingerprint)
    }
}
