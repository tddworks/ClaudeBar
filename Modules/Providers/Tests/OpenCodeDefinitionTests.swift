import DataSources
import Foundation
import Mockable
import Providers
import Quotas
import Testing

/// OpenCode Go as data: the usage API, and — with no key — one read-only
/// query of opencode's own database, worked out by SQLite.
@Suite @MainActor
struct OpenCodeDefinitionTests {
    static let usage = #"{"usage":{"rolling":{"status":"ok","percent":1,"resetsAt":"2026-08-24T15:34:00.000Z"},"weekly":{"status":"ok","percent":17,"resetsAt":"2026-08-29T00:00:00Z"},"monthly":{"status":"rate-limited","percent":98}}}"#
    static let now = Date(timeIntervalSince1970: 1775044800) // Apr 1, 2026 12:00 UTC
    /// What `opencode db … --format json` prints for the query: one row.
    static let localRow = #"[{"now_ms":1775044800000,"five_hour_cost":2.5,"five_hour_oldest_ms":1775037600000,"weekly_cost":7.5,"week_end_ms":1775433600000,"monthly_cost":15,"month_start_ms":1773502200000,"month_end_ms":1776177000000}]"#
    private func make(body: String = usage, status: Int = 200, key: String? = "personal", local: String = Self.localRow, exit: Int32 = 0, clock: Date = now, home: URL = FileManager.default.temporaryDirectory, env: [String:String]? = nil, available: Bool = true, vault: MemoryVault = MemoryVault()) throws -> Provider {
        let now = clock
        let def = try Providers.builtIn("opencode-go")
        let net = MockNetworkClient()
        given(net).request(.any).willProduce { @Sendable request in
            #expect(request.url?.absoluteString == "https://opencode.ai/zen/go/v1/usage")
            #expect(request.timeoutInterval == 15)
            #expect(["Bearer personal", "Bearer work", "Bearer file-key"].contains(request.value(forHTTPHeaderField:"Authorization") ?? ""))
            return (Data(body.utf8), HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:nil)!)
        }
        let cli = MockCLIExecutor()
        given(cli).locate(.any).willReturn(available ? "/test/opencode" : nil)
        given(cli).execute(binary:.any,args:.any,input:.any,timeout:.any,workingDirectory:.any,autoResponses:.any).willProduce { @Sendable binary,args,_,timeout,_,_ in
            #expect(binary == "opencode")
            #expect(timeout == 15)
            #expect(args.first == "db")
            #expect(args.suffix(2) == ["--format","json"])
            #expect(args.count == 4) // one fixed query, shown word for word on Import
            return CLIResult(output: local, exitCode: exit)
        }
        return Provider(definition:def,settings:InMemoryProviderSettings(),makeDataSource:{source,login in
            DataSources.make(source,providerId:def.id,cliExecutor:cli,network:net,makeTransport:{_,_,_,_ in MockRPCTransport()},scripts:Providers.builtInScripts,secrets:vault.scoped(to:login),environment:{ name in env.map { $0[name] } ?? (name == "OPENCODE_API_KEY" ? key : nil) },homeDirectory:home,now:{now})
        },vault:vault)
    }
    @Test func `server fixture retains quotas resets and durations`() async throws {
        let p = try make()
        #expect(p.name == "OpenCode Go")
        #expect(p.defaultAccount.isEnabled)
        let qs = try await p.defaultAccount.refresh().quotas
        #expect(qs.map(\.percentRemaining) == [99,83,0])
        #expect(qs.map(\.quotaType) == [.session,.weekly,.timeLimit("Monthly")])
        #expect(qs[0].resetsAt == Date(timeIntervalSince1970:1787585640))
        #expect(qs[0].window?.length == 18000)
        #expect(qs[1].window?.length == 604800)
        #expect(qs[2].window?.length == nil)
    }
    @Test(arguments:[("rolling","\"12.5\"",87.5),("weekly","130",0.0),("monthly","-4",100.0)])
    func `partial numeric and string windows are clamped`(_ fixture:(String,String,Double)) async throws {
        let qs = try await make(body:"{\"usage\":{\"\(fixture.0)\":{\"percent\":\(fixture.1)}}}").defaultAccount.refresh().quotas
        #expect(qs.count == 1)
        #expect(qs[0].percentRemaining == fixture.2)
    }
    @Test(arguments:["<html>","{}",#"{"usage":{}}"#])
    func `malformed or empty API responses remain failures`(_ body:String) async throws {
        await #expect(throws:UsageError.self) { try await make(body:body).defaultAccount.refresh() }
    }
    @Test func `401 does not fall back to the local account`() async throws {
        await #expect(throws:UsageError.sessionExpired(hint:"Run `opencode auth login` and pick OpenCode Zen to refresh your API key.")) { try await make(status:401).defaultAccount.refresh() }
    }
    @Test func `403 preserves subscription required`() async throws {
        await #expect(throws:UsageError.subscriptionRequired) { try await make(status:403).defaultAccount.refresh() }
    }
    @Test func `500 does not fall back`() async throws {
        await #expect(throws:UsageError.executionFailed("HTTP error: 500")) { try await make(status:500).defaultAccount.refresh() }
    }
    @Test func `a 429 is a rate limit and does not fall back`() async throws {
        await #expect { try await make(status:429).defaultAccount.refresh() } throws: { ($0 as? UsageError)?.tag == "rateLimited" }
    }
    @Test func `with no key, the local database gives money of each cap`() async throws {
        let p = try make(key:nil)
        #expect(await p.defaultAccount.isAvailable())
        let qs = try await p.defaultAccount.refresh().quotas
        #expect(qs.map(\.quotaType) == [.session,.weekly,.timeLimit("Monthly")])
        #expect(qs[0].left == .money(Money(Decimal(string: "9.50")!, currency: "USD"), of: Money(12, currency: "USD")))
        #expect(qs[1].left == .money(Money(Decimal(string: "22.50")!, currency: "USD"), of: Money(30, currency: "USD")))
        #expect(qs[2].left == .money(Money(Decimal(string: "45.00")!, currency: "USD"), of: Money(60, currency: "USD")))
        #expect(qs[0].resetsAt == Date(timeIntervalSince1970: 1775037600 + 18000)) // the oldest spend in 5h, plus 5h
        #expect(qs[1].resetsAt == Date(timeIntervalSince1970: 1775433600))
        #expect(qs[2].resetsAt == Date(timeIntervalSince1970: 1776177000))
        #expect(qs[2].window?.length == TimeInterval(2_674_800)) // the anchored month itself: Mar 14 to Apr 14
    }
    @Test func `with no spend yet, every cap is whole and the month states no window`() async throws {
        let row = #"[{"now_ms":1775044800000,"five_hour_cost":0,"five_hour_oldest_ms":null,"weekly_cost":0,"week_end_ms":1775433600000,"monthly_cost":0,"month_start_ms":null,"month_end_ms":null}]"#
        let qs = try await make(key:nil,local:row).defaultAccount.refresh().quotas
        #expect(qs.map(\.percentLeft) == [100,100,100])
        #expect(qs[0].resetsAt == Self.now.addingTimeInterval(18000))
        #expect(qs[2].resetsAt == nil)
        #expect(qs[2].window?.length == nil)
    }
    @Test(arguments:[-5.0,6.0,20.0]) func `money left never goes below zero`(_ cost:Double) async throws {
        let row = "[{\"now_ms\":1775044800000,\"five_hour_cost\":\(cost),\"weekly_cost\":0,\"week_end_ms\":1775433600000,\"monthly_cost\":0}]"
        let qs = try await make(key:nil,local:row).defaultAccount.refresh().quotas
        #expect(qs[0].dollarRemaining == Decimal(string: String(format: "%.2f", max(0, 12 - cost))))
    }
    @Test(arguments:["not JSON","[]",#"[{}]"#]) func `malformed local rows fail`(_ local:String) async throws {
        await #expect(throws:UsageError.self) { try await make(key:nil,local:local).defaultAccount.refresh() }
    }
    @Test func `a nonzero database exit is never healthy usage`() async throws {
        await #expect(throws:UsageError.executionFailed("`opencode` exited with code 1")) { try await make(key:nil,exit:1).defaultAccount.refresh() }
    }
    @Test func `missing key and CLI remain unavailable`() async throws {
        let p = try make(key:nil,available:false)
        #expect(!(await p.defaultAccount.isAvailable()))
        await #expect(throws:UsageError.cliNotFound("opencode")) { try await p.defaultAccount.refresh() }
    }

    // MARK: - The query itself, run by SQLite

    /// The definition's query against a fixture database, as of `now` (UTC).
    private func query(_ messages: [(at: String, cost: Double, provider: String)], now: String) throws -> [String: Any] {
        let definition = try Providers.builtIn("opencode-go")
        guard case .command(let call) = try #require(definition.dataSource("local")).fetch else {
            Issue.record("Expected a command"); return [:]
        }
        let sql = call.args[1].replacingOccurrences(of: "'now'", with: "'\(now)'")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = root.appendingPathComponent("opencode.db").path
        let formatter = ISO8601DateFormatter()
        var setup = "CREATE TABLE message(data TEXT, time_created INTEGER);"
        for message in messages {
            let ms = Int64(try #require(formatter.date(from: message.at)).timeIntervalSince1970 * 1000)
            setup += "INSERT INTO message VALUES ('{\"providerID\":\"\(message.provider)\",\"role\":\"assistant\",\"cost\":\(message.cost),\"time\":{\"created\":\(ms)}}', 0);"
        }
        for arguments in [[db, setup], ["-json", db, sql]] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()
            process.waitUntilExit()
            if arguments.count == 3 {
                let rows = try JSONSerialization.jsonObject(with: pipe.fileHandleForReading.readDataToEndOfFile()) as? [[String: Any]]
                return try #require(rows?.first)
            }
        }
        return [:]
    }

    private func ms(_ text: String) throws -> Int64 {
        Int64(try #require(ISO8601DateFormatter().date(from: text)).timeIntervalSince1970 * 1000)
    }

    @Test func `the query adds up 5 hours, the UTC week and the anchored month — only OpenCode Go`() throws {
        let row = try query([
            ("2026-01-31T14:30:00Z", 1.0, "opencode-go"),   // the first message: the month's anchor
            ("2026-04-29T09:00:00Z", 2.0, "opencode-go"),
            ("2026-04-30T15:00:00Z", 4.0, "opencode-go"),
            ("2026-05-04T10:00:00Z", 0.5, "opencode-go"),
            ("2026-05-04T13:00:00Z", 0.25, "opencode-go"),
            ("2026-05-04T14:00:00Z", 99, "another"),
        ], now: "2026-05-04 15:00:00")
        #expect(row["five_hour_cost"] as? Double == 0.75)
        #expect(row["five_hour_oldest_ms"] as? Int64 == (try ms("2026-05-04T10:00:00Z")))
        #expect(row["weekly_cost"] as? Double == 0.75)
        #expect(row["week_end_ms"] as? Int64 == (try ms("2026-05-11T00:00:00Z")))  // next UTC Monday
        // Anchored on the 31st: April has 30 days, so the month began Apr 30 14:30.
        #expect(row["month_start_ms"] as? Int64 == (try ms("2026-04-30T14:30:00Z")))
        #expect(row["month_end_ms"] as? Int64 == (try ms("2026-05-31T14:30:00Z")))
        #expect(row["monthly_cost"] as? Double == 4.75)
    }

    @Test(arguments: [
        ("2024-03-14T14:30:00Z", "2024-04-02 10:00:00", "2024-04-14T14:30:00Z"),
        ("2024-01-20T09:00:00Z", "2024-04-05 12:00:00", "2024-04-20T09:00:00Z"),
        // The 31st in a 29-day February: the month ends on its last day.
        ("2024-01-31T09:00:00Z", "2024-02-05 12:00:00", "2024-02-29T09:00:00Z"),
    ])
    func `the month is anchored on the first message's day, clamped to each month's last`(_ fixture: (String, String, String)) throws {
        let row = try query([(fixture.0, 1, "opencode-go")], now: fixture.1)
        #expect(row["month_end_ms"] as? Int64 == (try ms(fixture.2)))
    }

    @Test func `with no OpenCode Go messages the query gives zero spend and no month`() throws {
        let row = try query([("2026-05-04T14:00:00Z", 5, "another")], now: "2026-05-04 15:00:00")
        #expect(row["five_hour_cost"] as? Double == 0)
        #expect(row["monthly_cost"] as? Double == 0)
        #expect(row["month_start_ms"] == nil || row["month_start_ms"] is NSNull)
    }
    @Test func `added key account never falls back to the default local database`() async throws {
        let vault = MemoryVault()
        let p = try make(vault:vault)
        let work = try p.addAccount(filling:["apiKey":"work"])
        #expect(p.dataSources(for:work).map(\.kind) == ["api"])
        #expect(try await work.refresh().quotas.map(\.percentRemaining) == [99,83,0])
        vault.secrets["\(work.id).apiKey"] = nil
        await #expect(throws:UsageError.authenticationRequired) { try await work.refresh() }
    }
    @Test(arguments:["opencode-go","opencode","both"])
    func `both legacy auth file entries remain readable in XDG data home`(_ entry:String) async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:home) }
        let data = home.appendingPathComponent("data/opencode")
        try FileManager.default.createDirectory(at:data,withIntermediateDirectories:true)
        let auth = entry == "both" ? #"{"opencode-go":{"key":"file-key"},"opencode":{"key":"other-key"}}"# : "{\"\(entry)\":{\"type\":\"api\",\"key\":\"file-key\"}}"
        try Data(auth.utf8).write(to:data.appendingPathComponent("auth.json"))
        let p = try make(key:nil,home:home,env:["XDG_DATA_HOME":home.appendingPathComponent("data").path])
        #expect(try await p.defaultAccount.refresh().quotas.map(\.percentRemaining) == [99,83,0])
    }

}
