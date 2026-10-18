import DataSources
import Foundation
import Providers
import Quotas
import Testing

/// OpenCode's usage history as data: `opencode-go.json`'s `usageHistory`
/// reads opencode's own database with one read-only call, whose first query
/// the store can answer reads every place it keeps messages — `message`
/// (opencode 1), `session_message` (opencode 2), both after an upgrade — as
/// one log: every assistant message, whatever provider it drove, the range
/// asked for cut by `days(in:)` rather than by the queries (#566).
@Suite
struct OpenCodeUsageHistoryTests {
    typealias Place = OpenCodeStore.Place
    typealias Message = OpenCodeStore.Message

    /// The stores opencode leaves: one 1 wrote, one 2 started.
    static let places: [Place] = [.message, .sessionMessage]

    /// The log's query for a store holding `place` alone, run against one,
    /// as of one moment. The rewrite is what makes a window fail loudly: the
    /// queries carry no clock of their own, so a `'now'` reappearing in one
    /// is a window cutting days away, and the rows below are what it must
    /// not cut.
    private func rows(_ messages: [Message], in place: Place, now: String = "2026-04-25 12:00:00") throws -> [[String: Any]] {
        let definition = try #require(try ProviderFactory.builtIn("opencode-go").usageHistory)
        guard case .sqlite(let call) = definition.records.source else {
            Issue.record("OpenCode's usage history is not read from the database itself")
            return []
        }
        let query = try #require(call.queries.first { $0.requires == [place.rawValue] })
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = root.appendingPathComponent("opencode.db")
        try OpenCodeStore.make(at: db, places: [place], messages.map { var m = $0; m.place = place; return m })
        return try SQLiteFiles.rows(at: db, query.query.replacingOccurrences(of: "'now'", with: "'\(now)'"))
    }

    private func ms(_ iso: String) -> Int64 {
        Int64(ISO8601DateFormatter().date(from: iso)!.timeIntervalSince1970 * 1000)
    }

    @Test(arguments: places)
    func `should read every assistant message the database holds, whatever provider it drove`(_ place: Place) throws {
        let rows = try rows([
            Message(id: "msg_1", at: ms("2026-04-01T10:00:00Z"), provider: "opencode", input: 10, output: 5, cacheRead: 100), // Zen
            Message(id: "msg_2", at: ms("2026-04-20T10:00:00Z"), provider: "opencode-go", input: 20, output: 10, cost: 0.5),
            Message(id: "msg_3", at: ms("2026-04-25T10:00:00Z"), provider: "zai-coding-plan", input: 40, output: 20, cost: 0),
            Message(id: "msg_4", at: ms("2026-03-01T10:00:00Z"), provider: "opencode", input: 5, output: 5), // older than any window
        ], in: place)
        // Every assistant message, oldest first. The range asked for is cut by
        // `days(in:)` — the query never decides which days exist.
        #expect(rows.map { $0["id"] as? String } == ["msg_4", "msg_1", "msg_2", "msg_3"])
        #expect(rows.map { ($0["input"] as? NSNumber)?.intValue } == [5, 10, 20, 40])
        #expect((rows[2]["cost"] as? NSNumber)?.doubleValue == 0.5)
        #expect((rows[1]["at"] as? NSNumber)?.intValue == 1_775_037_600) // the time in seconds, not milliseconds
    }

    @Test(arguments: places)
    func `should leave out a message that is not an assistant's`(_ place: Place) throws {
        let rows = try rows([
            Message(id: "msg_1", at: ms("2026-04-25T10:00:00Z"), provider: "opencode", input: 10, output: 5),
            Message(id: "msg_2", at: ms("2026-04-25T11:00:00Z"), provider: "opencode", role: "user", input: 7, output: 0),
        ], in: place)
        #expect(rows.map { $0["id"] as? String } == ["msg_1"])
    }

    @Test(arguments: places)
    func `should answer a day any window of its own would have cut away`(_ place: Place) throws {
        // A window in the query would leave this day empty, and the ledger keeps
        // a closed day as read — so the wrong answer would be permanent.
        let rows = try rows([
            Message(id: "ancient", at: ms("2025-11-02T10:00:00Z"), provider: "opencode", input: 3, output: 2),
            Message(id: "recent", at: ms("2026-04-25T10:00:00Z"), provider: "opencode", input: 10, output: 5),
        ], in: place)
        #expect(rows.map { $0["id"] as? String } == ["ancient", "recent"])
    }

    @Test(arguments: places)
    func `should read a message without a cost, and skip one without a time`(_ place: Place) throws {
        let rows = try rows([
            Message(id: "msg_2", at: ms("2026-04-20T10:00:00Z"), provider: "opencode", input: 10, output: 5, cost: nil),
            Message(id: "msg_3", at: nil, provider: "opencode", input: 30, output: 15),
        ], in: place)
        #expect(rows.map { $0["id"] as? String } == ["msg_2"])
        #expect(rows[0]["cost"] == nil)
    }

    // MARK: - One log, whichever places the store has

    /// The log of a home whose store holds `places` and `messages`.
    private func log(_ places: Set<Place>, _ messages: [Message]) throws -> UsageLog {
        let definition = try #require(try ProviderFactory.builtIn("opencode-go").usageHistory)
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try OpenCodeStore.make(at: home.appendingPathComponent("data/opencode/opencode.db"), places: places, messages)
        return DataSources.makeUsageLog(definition, scripts: { _ in nil },
                                        environment: { $0 == "XDG_DATA_HOME" ? home.appendingPathComponent("data").path : nil },
                                        homeDirectory: home)
    }

    private static var today: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    @Test func `should read opencode 1's past and opencode 2's present of an upgraded store as one log`() async throws {
        let days = await try log([.message, .sessionMessage], [
            Message(id: "old_1", at: Self.today - 86_400_000, provider: "opencode", input: 1000, output: 500, place: .message),
            Message(id: "new_1", at: Self.today, provider: "opencode", input: 2000, output: 1000, place: .sessionMessage),
        ]).days(last: 2)
        #expect(days[0].totalTokens == 1500) // 1's past, from message
        #expect(days[1].totalTokens == 3000) // 2's present, from session_message
    }

    @Test func `should count a message an upgraded store holds in both places once`() async throws {
        let days = await try log([.message, .sessionMessage], [
            Message(id: "same", at: Self.today, provider: "opencode", input: 1000, output: 500, place: .message),
            Message(id: "same", at: Self.today, provider: "opencode", input: 1000, output: 500, place: .sessionMessage),
        ]).days(last: 1)
        #expect(days[0].totalTokens == 1500)
    }

    @Test(arguments: places)
    func `should read a store that only one version of opencode wrote`(_ place: Place) async throws {
        let days = await try log([place], [
            Message(id: "only_1", at: Self.today, provider: "opencode", input: 1000, output: 500, place: place),
        ]).days(last: 2)
        #expect(days[0].isEmpty) // yesterday
        #expect(days[1].totalTokens == 1500) // today
    }

    @Test func `should count every message of a busy day, however many`() async throws {
        // A fetch's answer stops at 1 000 rows; a day of history must not.
        let messages = (0..<1_200).map {
            Message(id: "m\($0)", at: Self.today - Int64($0), provider: "opencode", input: 1, output: 0)
        }
        #expect(await try log([.sessionMessage], messages).days(last: 1)[0].totalTokens == 1_200)
    }

    @Test func `should know the day's cost from the log itself, with no price list`() throws {
        let definition = try #require(try ProviderFactory.builtIn("opencode-go").usageHistory)
        #expect(definition.prices == nil)
        #expect(definition.records.shapes.allSatisfy { $0.cost != nil })
    }

    @Test func `should give an added login no usage history, so two logins never count one database twice`() throws {
        let definition = try ProviderFactory.builtIn("opencode-go")
        #expect(definition.usageHistory(forAccount: ["apiKey": "work"]) == nil)
    }
}
