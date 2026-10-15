import DataSources
import Foundation
import Providers
import Quotas
import Testing

/// OpenCode's usage history as data: `opencode-go.json`'s `usageHistory`
/// runs one fixed read-only query of opencode's own database — every
/// assistant message it holds, whatever provider it drove, as one total, the
/// range asked for cut by `days(in:)` rather than by the query.
@Suite
struct OpenCodeUsageHistoryTests {
    /// The definition's query against a fixture database, as of one moment.
    /// The rewrite is what makes a window fail loudly: the query carries no
    /// clock of its own, so a `'now'` reappearing in it is a window cutting
    /// days away, and the rows below are what it must not cut.
    private func rows(_ messages: [String], now: String = "2026-04-25 12:00:00") throws -> [[String: Any]] {
        let definition = try #require(try ProviderFactory.builtIn("opencode-go").usageHistory)
        guard case .command(let call) = definition.records.source else {
            Issue.record("OpenCode's usage history is not read from a command")
            return []
        }
        let sql = call.args[1].replacingOccurrences(of: "'now'", with: "'\(now)'")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = root.appendingPathComponent("opencode.db").path
        var setup = "CREATE TABLE message(data TEXT, time_created INTEGER);"
        for message in messages { setup += "INSERT INTO message VALUES ('\(message)', 0);" }
        for arguments in [[db, setup], ["-json", db, sql]] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()
            process.waitUntilExit()
            if arguments.count == 3 {
                return try JSONSerialization.jsonObject(with: pipe.fileHandleForReading.readDataToEndOfFile()) as? [[String: Any]] ?? []
            }
        }
        return []
    }

    /// An assistant message as opencode writes it: tokens, cost and time in `data`.
    private func message(id: String, at ms: Int64, provider: String, role: String = "assistant",
                         input: Int, output: Int, cacheRead: Int = 0, cacheWrite: Int = 0, cost: Double = 0) -> String {
        #"{"providerID":"\#(provider)","role":"\#(role)","id":"\#(id)","time":{"created":\#(ms)},"tokens":{"input":\#(input),"output":\#(output),"cache":{"read":\#(cacheRead),"write":\#(cacheWrite)}},"cost":\#(cost)}"#
    }

    private func ms(_ iso: String) -> Int64 {
        Int64(ISO8601DateFormatter().date(from: iso)!.timeIntervalSince1970 * 1000)
    }

    @Test(.needsSQLite) func `should read every assistant message the database holds, whatever provider it drove`() throws {
        let rows = try rows([
            message(id: "msg_1", at: ms("2026-04-01T10:00:00Z"), provider: "opencode", input: 10, output: 5, cacheRead: 100), // Zen
            message(id: "msg_2", at: ms("2026-04-20T10:00:00Z"), provider: "opencode-go", input: 20, output: 10, cost: 0.5),
            message(id: "msg_3", at: ms("2026-04-25T10:00:00Z"), provider: "zai-coding-plan", input: 40, output: 20, cost: 0),
            message(id: "msg_4", at: ms("2026-03-01T10:00:00Z"), provider: "opencode", input: 5, output: 5),                 // older than any window
            message(id: "msg_5", at: ms("2026-04-25T11:00:00Z"), provider: "opencode", role: "user", input: 7, output: 0),    // not an assistant
        ])
        // Every assistant message, oldest first. The range asked for is cut by
        // `days(in:)` — the query never decides which days exist.
        #expect(rows.map { $0["id"] as? String } == ["msg_4", "msg_1", "msg_2", "msg_3"])
        #expect(rows.map { $0["input"] as? Int } == [5, 10, 20, 40])
        #expect(rows[2]["cost"] as? Double == 0.5)
        #expect(rows[1]["at"] as? Int == 1_775_037_600) // the time in seconds, not milliseconds
    }

    @Test(.needsSQLite) func `should answer a day any window of its own would have cut away`() throws {
        // A window in the query would leave this day empty, and the ledger keeps
        // a closed day as read — so the wrong answer would be permanent.
        let rows = try rows([
            message(id: "ancient", at: ms("2025-11-02T10:00:00Z"), provider: "opencode", input: 3, output: 2),
            message(id: "recent", at: ms("2026-04-25T10:00:00Z"), provider: "opencode", input: 10, output: 5),
        ])
        #expect(rows.map { $0["id"] as? String } == ["ancient", "recent"])
    }

    @Test(.needsSQLite) func `should read a message without a cost, and skip one without a time`() throws {
        let rows = try rows([
            #"{"providerID":"opencode","role":"assistant","id":"msg_2","time":{"created":1775037600000},"tokens":{"input":10,"output":5}}"#,
            #"{"providerID":"opencode","role":"assistant","id":"msg_3","tokens":{"input":10,"output":5}}"#,
        ])
        #expect(rows.count == 1)
        #expect(rows[0]["cost"] == nil || rows[0]["cost"] is NSNull)
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
