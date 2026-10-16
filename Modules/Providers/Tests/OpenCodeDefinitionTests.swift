import DataSources
import Foundation
import Mockable
import Providers
import Quotas
import Testing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// OpenCode Go as data: the usage API, and — with no key — one read-only
/// query of opencode's own database, worked out by SQLite: v2's
/// `session_message` first, v1's `message` as the fallback (#566).
@Suite @MainActor
struct OpenCodeDefinitionTests {
    static let usage = #"{"usage":{"rolling":{"status":"ok","percent":1,"resetsAt":"2026-08-24T15:34:00.000Z"},"weekly":{"status":"ok","percent":17,"resetsAt":"2026-08-29T00:00:00Z"},"monthly":{"status":"rate-limited","percent":98}}}"#
    static let now = Date(timeIntervalSince1970: 1775044800) // Apr 1, 2026 12:00 UTC

    /// A layout of opencode's database: how its own CLI writes messages.
    enum Layout: CaseIterable, Sendable {
        /// v1: messages in `message`, the provider at the top of `data`.
        case v1
        /// v2: messages in `session_message` under `type`, the provider
        /// inside `data.model`, and `session_v2` beside them.
        case v2
    }

    /// An assistant message as the layout writes it, spent `cost` at `ms`.
    private static func message(layout: Layout, at ms: Int64, cost: Double, provider: String) -> String {
        switch layout {
        case .v1:
            return #"{"providerID":"\#(provider)","role":"assistant","cost":\#(cost),"time":{"created":\#(ms)}}"#
        case .v2:
            return #"{"model":{"providerID":"\#(provider)","id":"claude-x"},"cost":\#(cost),"time":{"created":\#(ms)}}"#
        }
    }

    /// A home whose opencode database holds `messages`; a home with no
    /// database at all when `layout` is `nil`.
    @discardableResult
    private func database(_ layout: Layout?, messages: [(at: Int64, cost: Double, provider: String)] = [],
                          home: URL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)) throws -> URL {
        guard let layout else { return home }
        let folder = home.appendingPathComponent("data/opencode")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var setup: String
        switch layout {
        case .v1:
            setup = "CREATE TABLE message(data TEXT, time_created INTEGER);"
            for message in messages {
                setup += "INSERT INTO message VALUES ('\(Self.message(layout: layout, at: message.at, cost: message.cost, provider: message.provider))', 0);"
            }
        case .v2:
            setup = "CREATE TABLE session_v2(id TEXT PRIMARY KEY);"
            setup += "CREATE TABLE session_message(id TEXT PRIMARY KEY, session_id TEXT NOT NULL, type TEXT NOT NULL, seq INTEGER NOT NULL, time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL, data TEXT NOT NULL);"
            for (index, message) in messages.enumerated() {
                setup += "INSERT INTO session_message VALUES ('msg_\(index)', 'ses_1', 'assistant', \(index), 0, 0, '\(Self.message(layout: layout, at: message.at, cost: message.cost, provider: message.provider))');"
            }
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [folder.appendingPathComponent("opencode.db").path, setup]
        try process.run()
        process.waitUntilExit()
        return home
    }

    /// A provider whose default login has `key`, reading the database of
    /// `layout` under `home` (fresh when nil). The database is written only
    /// when the local source can run — an API test reads no database, and
    /// the fixture needs this platform's `sqlite3` to exist.
    private func make(body: String = usage, status: Int = 200, key: String? = "personal",
                      layout: Layout? = .v2, messages: [(at: Int64, cost: Double, provider: String)] = [],
                      clock: Date = now, home: URL? = nil, available: Bool = true,
                      vault: MemoryVault = MemoryVault()) throws -> Provider {
        let reading = key == nil
        let home = try database(reading ? layout : nil, messages: reading ? messages : [],
                                home: home ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let env = ["XDG_DATA_HOME": home.appendingPathComponent("data").path]
        let def = try ProviderFactory.builtIn("opencode-go")
        let net = MockNetworkClient()
        given(net).request(.any).willProduce { @Sendable request in
            #expect(request.url?.absoluteString == "https://opencode.ai/zen/go/v1/usage")
            #expect(request.timeoutInterval == 15)
            #expect(["Bearer personal", "Bearer work", "Bearer file-key"].contains(request.value(forHTTPHeaderField:"Authorization") ?? ""))
            return (Data(body.utf8), HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:nil)!)
        }
        let cli = MockCLIExecutor()
        given(cli).locate(.any).willReturn(available ? "/test/opencode" : nil)
        return Provider(definition:def,settings:InMemoryProviderSettings(),makeDataSource:{source,login in
            DataSources.make(source,providerId:def.id,cliExecutor:cli,network:net,makeTransport:{_,_,_,_ in MockRPCTransport()},scripts:ProviderFactory.builtInScripts,secrets:vault.scoped(to:login),environment:{ name in env[name] ?? (name == "OPENCODE_API_KEY" ? key : nil) },homeDirectory:home,now:{clock})
        },vault:vault)
    }

    private func ms(_ iso: String) -> Int64 {
        Int64(ISO8601DateFormatter().date(from: iso)!.timeIntervalSince1970 * 1000)
    }

    @Test(.needsScriptEngine) func `should show the 5-hour, weekly and monthly quotas with their resets and windows when OpenCode Go answers`() async throws {
        let p = try make()
        #expect(p.name == "OpenCode Go")
        #expect(!p.defaultAccount.isPaused)
        let qs = try await p.refreshPlain().quotas
        #expect(qs.map(\.percentRemaining) == [99,83,0])
        #expect(qs.map(\.quotaType) == [.session,.weekly,.timeLimit("Monthly")])
        #expect(qs[0].resetsAt == Date(timeIntervalSince1970:1787585640))
        #expect(qs[0].window?.length == 18000)
        #expect(qs[1].window?.length == 604800)
        #expect(qs[2].window?.length == nil)
    }
    @Test(.needsScriptEngine, arguments:[("rolling","\"12.5\"",87.5),("weekly","130",0.0),("monthly","-4",100.0)])
    func `should keep the percent left between 0 and 100 when OpenCode Go reports one window, as a number or text`(_ fixture:(String,String,Double)) async throws {
        let qs = try await make(body:"{\"usage\":{\"\(fixture.0)\":{\"percent\":\(fixture.1)}}}").refreshPlain().quotas
        #expect(qs.count == 1)
        #expect(qs[0].percentRemaining == fixture.2)
    }
    @Test(arguments:["<html>","{}",#"{"usage":{}}"#])
    func `should fail to read usage when OpenCode Go answers with no usage`(_ body:String) async throws {
        await #expect(throws:UsageError.self) { try await make(body:body).refreshPlain() }
    }
    @Test func `should ask to refresh the API key, not read the local database, when OpenCode Go refuses the key`() async throws {
        await #expect(throws:UsageError.sessionExpired(hint:"Run `opencode auth login` and pick OpenCode Zen to refresh your API key.")) { try await make(status:401).refreshPlain() }
    }
    @Test func `should say a subscription is required when OpenCode Go forbids the key`() async throws {
        await #expect(throws:UsageError.subscriptionRequired) { try await make(status:403).refreshPlain() }
    }
    @Test func `should show the server error, not read the local database, when OpenCode Go is down`() async throws {
        await #expect(throws:UsageError.executionFailed("HTTP error: 500")) { try await make(status:500).refreshPlain() }
    }
    @Test func `should show a rate limit, not read the local database, when OpenCode Go is rate-limiting`() async throws {
        await #expect { try await make(status:429).refreshPlain() } throws: { ($0 as? UsageError)?.tag == "rateLimited" }
    }

    /// The spend of the local tests below, relative to the run: the month's
    /// anchor long ago, and every window's spend a minute ago — the query
    /// works its windows out of SQLite's own `'now'`, so a fixed date would
    /// fall out of them. The exact windows are the SQL-level tests' to pin.
    private static func spend(now: Date) -> [(at: Int64, cost: Double, provider: String)] {
        let ms = { (offset: TimeInterval) in Int64((now + offset).timeIntervalSince1970 * 1000) }
        return [
            (ms(-400 * 86_400), 1.0, "opencode-go"),  // the first message: the month's anchor
            (ms(-60.0), 0.5, "opencode-go"),          // inside every window
            (ms(-30.0), 0.25, "opencode-go"),
            (ms(-20.0), 99, "another"),               // not OpenCode Go's
        ]
    }

    @Test(.needsScriptEngine, arguments: Layout.allCases)
    func `should show dollars left of each cap from opencode's own database when there is no key`(_ layout: Layout) async throws {
        let p = try make(key:nil, layout:layout, messages:Self.spend(now: Date()))
        #expect(await p.isPlainAvailable())
        let qs = try await p.refreshPlain().quotas
        #expect(qs.map(\.quotaType) == [.session,.weekly,.timeLimit("Monthly")])
        #expect(qs[0].left == .money(Money(Decimal(string: "11.25")!, currency: "USD"), of: Money(12, currency: "USD")))
        #expect(qs[1].left == .money(Money(Decimal(string: "29.25")!, currency: "USD"), of: Money(30, currency: "USD")))
        #expect(qs[2].left == .money(Money(Decimal(string: "59.25")!, currency: "USD"), of: Money(60, currency: "USD")))
        // The 5-hour window ends 5 hours after its oldest spend; the week,
        // next UTC Monday; the month, its anchor + 1. The SQL-level tests pin
        // the exact resets; here they are just the windows they should be.
        #expect(abs((qs[0].resetsAt?.timeIntervalSince(Date()) ?? 0) - (5 * 3600 - 60)) < 120)
        #expect((qs[1].resetsAt?.timeIntervalSince(Date()) ?? 0) > 3600) // a reset still ahead
        #expect(qs[2].resetsAt != nil)
        #expect(qs[2].window?.length != nil) // the anchored month itself
    }
    @Test(.needsScriptEngine, arguments: Layout.allCases)
    func `should show every cap full and no monthly window when nothing has been spent yet`(_ layout: Layout) async throws {
        let qs = try await make(key:nil, layout:layout).refreshPlain().quotas
        #expect(qs.map(\.percentLeft) == [100,100,100])
        #expect(abs(qs[0].resetsAt!.timeIntervalSince(Date()) - 18000) < 60) // now + 5h, by SQLite's clock
        #expect(qs[2].resetsAt == nil)
        #expect(qs[2].window?.length == nil)
    }
    @Test(.needsScriptEngine)
    func `should read only what v2 wrote, never what the database kept from v1`() async throws {
        // What a v1 → v2 upgrade leaves behind: the old table, with a huge
        // spend inside the 5-hour window. The v2 layout reads v2's alone.
        let stale = Int64(Date().timeIntervalSince1970 * 1000) - 600_000
        let home = try database(.v2, messages: Self.spend(now: Date()))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [home.appendingPathComponent("data/opencode/opencode.db").path,
                             "CREATE TABLE message(data TEXT, time_created INTEGER); INSERT INTO message VALUES ('{\"providerID\":\"opencode-go\",\"role\":\"assistant\",\"cost\":900,\"time\":{\"created\":\(stale)}}', 0);"]
        try process.run()
        process.waitUntilExit()
        let env = ["XDG_DATA_HOME": home.appendingPathComponent("data").path]
        let def = try ProviderFactory.builtIn("opencode-go")
        let clock = Self.now
        let p = Provider(definition:def,settings:InMemoryProviderSettings(),makeDataSource:{source,login in
            DataSources.make(source,providerId:def.id,cliExecutor:MockCLIExecutor(),network:MockNetworkClient(),makeTransport:{_,_,_,_ in MockRPCTransport()},scripts:ProviderFactory.builtInScripts,secrets:MemoryVault().scoped(to:login),environment:{ name in env[name] },homeDirectory:home,now:{clock})
        },vault:MemoryVault())
        let qs = try await p.refreshPlain().quotas
        #expect(qs[0].left == .money(Money(Decimal(string: "11.25")!, currency: "USD"), of: Money(12, currency: "USD")))
    }
    @Test(.needsScriptEngine, arguments:[-5.0,6.0,20.0]) func `should never show less than nothing left of a cap`(_ cost:Double) async throws {
        let spend: [(at: Int64, cost: Double, provider: String)] = [(Int64(Date().timeIntervalSince1970 * 1000) - 60_000, cost, "opencode-go")]
        let qs = try await make(key:nil, messages:spend).refreshPlain().quotas
        #expect(qs[0].dollarRemaining == Decimal(string: String(format: "%.2f", max(0, 12 - cost))))
    }
    @Test(.needsScriptEngine) func `should fail, never show usage, when there is no database`() async throws {
        await #expect(throws:UsageError.self) { try await make(key:nil, layout:nil).refreshPlain() }
    }
    @Test(.needsScriptEngine) func `should answer from the database alone when there is no key and no CLI`() async throws {
        // The database is read directly: the CLI's own query door came and
        // went with v2 (#566), so the local mode never needed it in between.
        let p = try make(key:nil, available:false)
        #expect(await p.isPlainAvailable())
        let qs = try await p.refreshPlain().quotas
        #expect(qs.map(\.quotaType) == [.session,.weekly,.timeLimit("Monthly")])
    }

    // MARK: - The queries themselves, run by SQLite

    /// One layout's query against a fixture database, as of `now` (UTC).
    private func query(_ layout: Layout, _ messages: [(at: String, cost: Double, provider: String)], now: String) throws -> [String: Any] {
        let definition = try ProviderFactory.builtIn("opencode-go")
        let kind = layout == .v2 ? "local" : "local1"
        guard case .sqlite(let call) = try #require(definition.dataSource(kind)).fetch else {
            Issue.record("Expected the \(kind) source to read the database itself"); return [:]
        }
        let sql = call.query.replacingOccurrences(of: "'now'", with: "'\(now)'")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = root.appendingPathComponent("opencode.db").path
        let formatter = ISO8601DateFormatter()
        var setup: String
        switch layout {
        case .v1:
            setup = "CREATE TABLE message(data TEXT, time_created INTEGER);"
            for message in messages {
                let ms = Int64(try #require(formatter.date(from: message.at)).timeIntervalSince1970 * 1000)
                setup += "INSERT INTO message VALUES ('{\"providerID\":\"\(message.provider)\",\"role\":\"assistant\",\"cost\":\(message.cost),\"time\":{\"created\":\(ms)}}', 0);"
            }
        case .v2:
            setup = "CREATE TABLE session_v2(id TEXT PRIMARY KEY);"
            setup += "CREATE TABLE session_message(id TEXT PRIMARY KEY, session_id TEXT NOT NULL, type TEXT NOT NULL, seq INTEGER NOT NULL, time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL, data TEXT NOT NULL);"
            for (index, message) in messages.enumerated() {
                let ms = Int64(try #require(formatter.date(from: message.at)).timeIntervalSince1970 * 1000)
                setup += "INSERT INTO session_message VALUES ('msg_\(index)', 'ses_1', 'assistant', \(index), 0, 0, '{\"model\":{\"providerID\":\"\(message.provider)\",\"id\":\"claude-x\"},\"cost\":\(message.cost),\"time\":{\"created\":\(ms)}}');"
            }
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

    @Test(.needsSQLite, arguments: Layout.allCases) func `should add up the last 5 hours, the UTC week and the anchored month of OpenCode Go spend only`(_ layout: Layout) throws {
        let row = try query(layout, [
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

    @Test(.needsSQLite, arguments: Layout.allCases.flatMap { layout in
        [
            ("2024-03-14T14:30:00Z", "2024-04-02 10:00:00", "2024-04-14T14:30:00Z", layout),
            ("2024-01-20T09:00:00Z", "2024-04-05 12:00:00", "2024-04-20T09:00:00Z", layout),
            // The 31st in a 29-day February: the month ends on its last day.
            ("2024-01-31T09:00:00Z", "2024-02-05 12:00:00", "2024-02-29T09:00:00Z", layout),
        ]
    })
    func `should start each month on the first message's day, or the month's last day when it is shorter`(_ fixture: (String, String, String, Layout)) throws {
        let row = try query(fixture.3, [(fixture.0, 1, "opencode-go")], now: fixture.1)
        #expect(row["month_end_ms"] as? Int64 == (try ms(fixture.2)))
    }

    @Test(.needsSQLite, arguments: Layout.allCases) func `should show no spend and no month when there are no OpenCode Go messages`(_ layout: Layout) throws {
        let row = try query(layout, [("2026-05-04T14:00:00Z", 5, "another")], now: "2026-05-04 15:00:00")
        #expect(row["five_hour_cost"] as? Double == 0)
        #expect(row["monthly_cost"] as? Double == 0)
        #expect(row["month_start_ms"] == nil || row["month_start_ms"] is NSNull)
    }

    @Test(.needsSQLite) func `should say so when the database is not v2's`() throws {
        // The v1 query carries no guard: the guard is the v2 query's alone.
        let row = try query(.v1, [("2026-05-04T14:00:00Z", 5, "opencode-go")], now: "2026-05-04 15:00:00")
        #expect(row["is_v2"] == nil)
        let v2 = try query(.v2, [("2026-05-04T14:00:00Z", 5, "opencode-go")], now: "2026-05-04 15:00:00")
        #expect(v2["is_v2"] as? Int64 == 1)
    }

    @Test(.needsScriptEngine) func `should use only an added login's own key, never the local database, and ask to sign in when it is gone`() async throws {
        let vault = MemoryVault()
        let p = try make(vault:vault)
        let work = try p.accounts.add(filling:["apiKey":"work"])
        #expect(p.dataSources(for:work).map(\.kind) == ["api"])
        #expect(try await p.refresh(work).quotas.map(\.percentRemaining) == [99,83,0])
        vault.secrets["\(work.id).apiKey"] = nil
        await #expect(throws:UsageError.authenticationRequired) { try await p.refresh(work) }
    }
    @Test(.needsScriptEngine, arguments:["opencode-go","opencode","both"])
    func `should use the key opencode saved in its auth file under XDG_DATA_HOME`(_ entry:String) async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:home) }
        let data = home.appendingPathComponent("data/opencode")
        try FileManager.default.createDirectory(at:data,withIntermediateDirectories:true)
        let auth = entry == "both" ? #"{"opencode-go":{"key":"file-key"},"opencode":{"key":"other-key"}}"# : "{\"\(entry)\":{\"type\":\"api\",\"key\":\"file-key\"}}"
        try Data(auth.utf8).write(to:data.appendingPathComponent("auth.json"))
        let p = try make(key:nil, layout:nil, home:home)
        #expect(try await p.refreshPlain().quotas.map(\.percentRemaining) == [99,83,0])
    }
}
