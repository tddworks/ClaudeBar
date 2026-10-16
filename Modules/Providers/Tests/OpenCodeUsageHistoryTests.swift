import DataSources
import Foundation
import Providers
import Quotas
import Testing

/// OpenCode's usage history as data: `opencode-go.json`'s `usageHistory`
/// runs one fixed read-only query per layout of opencode's own database —
/// v2's `session_message` and, as `also`, v1's `message` — and the two
/// answers are read as one log: every assistant message the database holds,
/// whatever provider it drove, the range asked for cut by `days(in:)` rather
/// than by the queries (#566).
@Suite
struct OpenCodeUsageHistoryTests {
    /// A layout of opencode's database: how its own CLI writes messages.
    enum Layout: Sendable { case v1, v2 }

    /// One layout's query against a fixture database, as of one moment. The
    /// rewrite is what makes a window fail loudly: the queries carry no clock
    /// of their own, so a `'now'` reappearing in one is a window cutting days
    /// away, and the rows below are what it must not cut.
    private func rows(_ messages: [String], layout: Layout, now: String = "2026-04-25 12:00:00") throws -> [[String: Any]] {
        let definition = try #require(try ProviderFactory.builtIn("opencode-go").usageHistory)
        let source: UsageLog.Records.Source = layout == .v2 ? definition.records.source
            : try #require(definition.records.also)
        guard case .sqlite(let call) = source else {
            Issue.record("OpenCode's usage history is not read from the database itself")
            return []
        }
        let sql = call.query.replacingOccurrences(of: "'now'", with: "'\(now)'")
        return try Self.query(sql, database: Self.build(messages, layout: layout))
    }

    /// A fixture database: `folder` to write it in, the SQL that fills it.
    static func build(_ messages: [String], layout: Layout, in folder: URL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)) -> (folder: URL, setup: String) {
        var setup: String
        switch layout {
        case .v1:
            setup = "CREATE TABLE message(data TEXT, time_created INTEGER);"
            for message in messages { setup += "INSERT INTO message VALUES ('\(message)', 0);" }
        case .v2:
            setup = "CREATE TABLE session_v2(id TEXT PRIMARY KEY);"
            setup += "CREATE TABLE session_message(id TEXT PRIMARY KEY, session_id TEXT NOT NULL, type TEXT NOT NULL, seq INTEGER NOT NULL, time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL, data TEXT NOT NULL);"
            for (index, message) in messages.enumerated() {
                setup += "INSERT INTO session_message VALUES ('v2_\(index)', 'ses_1', 'assistant', \(index), 0, 0, '\(message)');"
            }
        }
        return (folder, setup)
    }

    /// `sql` run against the fixture database, answered as `sqlite3 --json`.
    static func query(_ sql: String, database: (folder: URL, setup: String), name: String = "opencode.db") throws -> [[String: Any]] {
        try FileManager.default.createDirectory(at: database.folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: database.folder) }
        let db = database.folder.appendingPathComponent(name).path
        for arguments in [[db, database.setup], ["-json", db, sql]] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
            process.arguments = arguments
            let pipe = Pipe()
            let errors = Pipe()
            process.standardOutput = pipe
            process.standardError = errors
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let why = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                Issue.record("sqlite3 \(arguments.dropFirst()) failed: \(why)")
                return []
            }
            if arguments.count == 3 {
                return try JSONSerialization.jsonObject(with: pipe.fileHandleForReading.readDataToEndOfFile()) as? [[String: Any]] ?? []
            }
        }
        return []
    }

    /// An assistant message as the layout writes it: tokens, cost and time in
    /// `data` — v1 with the provider and role at the top, v2 inside `model`.
    /// A `nil` time or cost leaves the field out, as a message without it is.
    private func message(id: String, at ms: Int64?, provider: String, layout: Layout,
                         input: Int, output: Int, cacheRead: Int = 0, cacheWrite: Int = 0, cost: Double? = 0,
                         role: String = "assistant") -> String {
        var fields = [layout == .v1 ? #""providerID":"\#(provider)","role":"\#(role)""#
                      : #""model":{"providerID":"\#(provider)","id":"claude-x"}"#,
                      #""id":"\#(id)""#]
        if let ms { fields.append(#""time":{"created":\#(ms)}"#) }
        fields.append(#""tokens":{"input":\#(input),"output":\#(output),"cache":{"read":\#(cacheRead),"write":\#(cacheWrite)}}"#)
        if let cost { fields.append(#""cost":\#(cost)"#) }
        return "{" + fields.joined(separator: ",") + "}"
    }

    private func ms(_ iso: String) -> Int64 {
        Int64(ISO8601DateFormatter().date(from: iso)!.timeIntervalSince1970 * 1000)
    }

    @Test(.needsSQLite, arguments: [OpenCodeUsageHistoryTests.Layout.v1, .v2])
    func `should read every assistant message the database holds, whatever provider it drove`(_ layout: Layout) throws {
        let rows = try rows([
            message(id: "msg_1", at: ms("2026-04-01T10:00:00Z"), provider: "opencode", layout: layout, input: 10, output: 5, cacheRead: 100), // Zen
            message(id: "msg_2", at: ms("2026-04-20T10:00:00Z"), provider: "opencode-go", layout: layout, input: 20, output: 10, cost: 0.5),
            message(id: "msg_3", at: ms("2026-04-25T10:00:00Z"), provider: "zai-coding-plan", layout: layout, input: 40, output: 20, cost: 0),
            message(id: "msg_4", at: ms("2026-03-01T10:00:00Z"), provider: "opencode", layout: layout, input: 5, output: 5), // older than any window
        ], layout: layout)
        // Every assistant message, oldest first. The range asked for is cut by
        // `days(in:)` — the query never decides which days exist.
        #expect(rows.map { $0["id"] as? String } == ["msg_4", "msg_1", "msg_2", "msg_3"])
        #expect(rows.map { $0["input"] as? Int } == [5, 10, 20, 40])
        #expect(rows[2]["cost"] as? Double == 0.5)
        #expect(rows[1]["at"] as? Int == 1_775_037_600) // the time in seconds, not milliseconds
    }

    @Test(.needsSQLite) func `should leave out a message that is not an assistant's`() throws {
        let user = try rows([
            message(id: "msg_1", at: ms("2026-04-25T10:00:00Z"), provider: "opencode", layout: .v1, input: 10, output: 5),
            message(id: "msg_2", at: ms("2026-04-25T11:00:00Z"), provider: "opencode", layout: .v1, input: 7, output: 0, role: "user"),
        ], layout: .v1)
        #expect(user.map { $0["id"] as? String } == ["msg_1"])
    }

    @Test(.needsSQLite, arguments: [OpenCodeUsageHistoryTests.Layout.v1, .v2])
    func `should answer a day any window of its own would have cut away`(_ layout: Layout) throws {
        // A window in the query would leave this day empty, and the ledger keeps
        // a closed day as read — so the wrong answer would be permanent.
        let rows = try rows([
            message(id: "ancient", at: ms("2025-11-02T10:00:00Z"), provider: "opencode", layout: layout, input: 3, output: 2),
            message(id: "recent", at: ms("2026-04-25T10:00:00Z"), provider: "opencode", layout: layout, input: 10, output: 5),
        ], layout: layout)
        #expect(rows.map { $0["id"] as? String } == ["ancient", "recent"])
    }

    @Test(.needsSQLite, arguments: [OpenCodeUsageHistoryTests.Layout.v1, .v2])
    func `should read a message without a cost, and skip one without a time`(_ layout: Layout) throws {
        let rows = try rows([
            message(id: "msg_2", at: ms("2026-04-20T10:00:00Z"), provider: "opencode", layout: layout, input: 10, output: 5, cost: nil),
            message(id: "msg_3", at: nil, provider: "opencode", layout: layout, input: 30, output: 15),
        ], layout: layout)
        #expect(rows.count == 1)
        #expect(rows[0]["id"] as? String == "msg_2")
        #expect(rows[0]["cost"] == nil || rows[0]["cost"] is NSNull)
    }

    // MARK: - One log out of both layouts

    /// The log of a home whose database holds both layouts' messages.
    private func makeLog(v1: [String], v2: [String]) throws -> UsageLog {
        let definition = try #require(try ProviderFactory.builtIn("opencode-go").usageHistory)
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = home.appendingPathComponent("data/opencode")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let v1Part = Self.build(v1, layout: .v1).setup
        let v2Part = Self.build(v2, layout: .v2).setup
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [folder.appendingPathComponent("opencode.db").path, v1Part + v2Part]
        try process.run()
        process.waitUntilExit()
        return DataSources.makeUsageLog(definition, scripts: { _ in nil },
                                        environment: { $0 == "XDG_DATA_HOME" ? home.appendingPathComponent("data").path : nil },
                                        homeDirectory: home)
    }

    @Test(.needsSQLite) func `should read v1's past and v2's present as one log`() async throws {
        let today = Int64(Date().timeIntervalSince1970 * 1000)
        let yesterday = today - 86_400_000
        let log = try makeLog(
            v1: [message(id: "old_1", at: yesterday, provider: "opencode", layout: .v1, input: 1000, output: 500)],
            v2: [message(id: "new_1", at: today, provider: "opencode", layout: .v2, input: 2000, output: 1000)])
        let days = await log.days(last: 2)
        #expect(days[0].totalTokens == 1500) // v1's past, from message
        #expect(days[1].totalTokens == 3000) // v2's present, from session_message
    }

    @Test(.needsSQLite, arguments: [OpenCodeUsageHistoryTests.Layout.v1, .v2])
    func `should read a database that only one layout wrote`(_ layout: Layout) async throws {
        let message = message(id: "only_1", at: Int64(Date().timeIntervalSince1970 * 1000), provider: "opencode", layout: layout, input: 1000, output: 500)
        let log = try makeLog(
            v1: layout == .v1 ? [message] : [],
            v2: layout == .v2 ? [message] : [])
        let days = await log.days(last: 2)
        #expect(days[0].isEmpty) // yesterday
        #expect(days[1].totalTokens == 1500) // today
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
