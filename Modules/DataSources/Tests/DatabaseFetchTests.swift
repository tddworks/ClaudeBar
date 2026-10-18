import Foundation
import Mockable
import Quotas
import Testing
@testable import DataSources

/// `fetch.sqlite` — rows of another app's own database as the answer, read
/// through the same read-only query as the `sqlite` key lookup
/// (ENGINE_DESIGN §2.9). The database is never written.
@Suite
struct DatabaseFetchTests {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    /// A database at `relative` under `root`, made with the one SQLite.
    @discardableResult
    private func database(_ sql: String, at relative: String = "state.vscdb") throws -> URL {
        let file = root.appendingPathComponent(relative)
        try SQLiteFiles.make(at: file, sql)
        return file
    }

    private func fetcher(path: PathPattern, query: String) -> SQLiteFetcher {
        SQLiteFetcher(call: SQLiteCall(path: path, query: query), homeDirectory: root, environment: { _ in nil })
    }

    private func rows(_ response: Response) throws -> [[String: String]] {
        try #require(try JSONSerialization.jsonObject(with: response.body) as? [[String: String]])
    }

    /// `{"planName":"Pro"}` as UTF-16LE bytes, the way some apps store text.
    private static let utf16Hex = Data(#"{"planName":"Pro"}"#.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })
        .map { String(format: "%02X", $0) }.joined()

    @Test
    func `should answer with the rows the query reads, each column as text`() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try database("CREATE TABLE ItemTable(key TEXT, value TEXT); INSERT INTO ItemTable VALUES ('plan', '{\"planName\":\"Pro\"}'), ('other', 'x');")

        let response = try await fetcher(path: "~/state.vscdb", query: "SELECT value FROM ItemTable WHERE key = 'plan'").fetch(with: nil)

        #expect(try rows(response) == [["value": #"{"planName":"Pro"}"#]])
    }

    /// SQL a definition wrote against the Mac's own SQLite, which takes a
    /// double-quoted string and has the math functions, reads the same here.
    @Test(arguments: [
        (#"SELECT value FROM ItemTable WHERE key = "plan""#, #"{"planName":"Pro"}"#),
        ("SELECT CAST(floor(pow(2, 3) + 0.5) AS INTEGER) AS value", "8"),
    ])
    func `should read a query written for the Mac's SQLite`(_ query: String, _ value: String) async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try database("CREATE TABLE ItemTable(key TEXT, value TEXT); INSERT INTO ItemTable VALUES ('plan', '{\"planName\":\"Pro\"}');")

        let response = try await fetcher(path: "~/state.vscdb", query: query).fetch(with: nil)

        #expect(try rows(response) == [["value": value]])
    }

    @Test(arguments: [true, false])
    func `should read text an app stored as a UTF-8 or UTF-16 BLOB`(_ utf16: Bool) async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let hex = utf16 ? Self.utf16Hex : Data(#"{"planName":"Pro"}"#.utf8).map { String(format: "%02X", $0) }.joined()
        try database("CREATE TABLE ItemTable(key TEXT, value BLOB); INSERT INTO ItemTable VALUES ('plan', X'\(hex)');")

        let response = try await fetcher(path: "~/state.vscdb", query: "SELECT value FROM ItemTable").fetch(with: nil)

        #expect(try rows(response) == [["value": #"{"planName":"Pro"}"#]])
    }

    @Test
    func `should answer with no rows when the query finds nothing`() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try database("CREATE TABLE ItemTable(key TEXT, value TEXT);")

        let response = try await fetcher(path: "~/state.vscdb", query: "SELECT value FROM ItemTable").fetch(with: nil)

        #expect(try rows(response) == [])
    }

    @Test
    func `should refuse a query that would change the app's database, and leave it as it was`() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try database("CREATE TABLE ItemTable(key TEXT, value TEXT); INSERT INTO ItemTable VALUES ('a', 'b');")
        let before = try Data(contentsOf: file)

        await #expect(throws: UsageError.self) {
            try await fetcher(path: "~/state.vscdb", query: "DELETE FROM ItemTable").fetch(with: nil)
        }
        _ = try await fetcher(path: "~/state.vscdb", query: "SELECT value FROM ItemTable").fetch(with: nil)
        #expect(try Data(contentsOf: file) == before)
    }

    @Test
    func `should be configured only while the database is there`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(!fetcher(path: "~/state.vscdb", query: "SELECT 1").isReady())
        try database("CREATE TABLE t(v TEXT);")
        #expect(fetcher(path: "~/state.vscdb", query: "SELECT 1").isReady())
    }

    @Test
    func `should read the most recently changed database a star matches`() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let old = try database("CREATE TABLE t(v TEXT); INSERT INTO t VALUES ('old');", at: "App/Old/state.vscdb")
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-3600)], ofItemAtPath: old.path)
        try database("CREATE TABLE t(v TEXT); INSERT INTO t VALUES ('new');", at: "App/New/state.vscdb")

        let response = try await fetcher(path: "~/App/*/state.vscdb", query: "SELECT v FROM t").fetch(with: nil)

        #expect(try rows(response) == [["v": "new"]])
    }

    @Test
    func `should come from a definition and name no host and run nothing`() throws {
        let fetch = try JSONDecoder().decode(Fetch.self, from: Data(#"{"sqlite":{"path":"~/state.vscdb","query":"SELECT value FROM ItemTable"}}"#.utf8))
        #expect(fetch == .sqlite(SQLiteCall(path: "~/state.vscdb", query: "SELECT value FROM ItemTable")))
        #expect(fetch.connection.urls.isEmpty)
        #expect(fetch.connection.commands.isEmpty)
        #expect(try JSONDecoder().decode(Fetch.self, from: try JSONEncoder().encode(fetch)) == fetch)
    }

    @Test
    func `should find a key an app stored as a UTF-16 BLOB`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let hex = Data("secret-token".utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }).map { String(format: "%02X", $0) }.joined()
        try database("CREATE TABLE items(value BLOB); INSERT INTO items VALUES (X'\(hex)');")

        let reader = SQLiteReader(file: SQLiteCredential(path: "~/state.vscdb", query: "SELECT value AS token FROM items",
                                                         fields: ["token": "$.token"]),
                                  homeDirectory: root, environment: { _ in nil })
        #expect(try reader.find()?.credential.token == "secret-token")
    }
}
