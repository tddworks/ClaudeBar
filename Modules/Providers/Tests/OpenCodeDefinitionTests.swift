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
/// call on opencode's own database, worked out by SQLite. The call reads
/// every place the store keeps messages: `message` (opencode 1),
/// `session_message` (opencode 2), or both after an upgrade (#566).
@Suite @MainActor
struct OpenCodeDefinitionTests {
    typealias Place = OpenCodeStore.Place
    static let usage = #"{"usage":{"rolling":{"status":"ok","percent":1,"resetsAt":"2026-08-24T15:34:00.000Z"},"weekly":{"status":"ok","percent":17,"resetsAt":"2026-08-29T00:00:00Z"},"monthly":{"status":"rate-limited","percent":98}}}"#
    static let now = Date(timeIntervalSince1970: 1775044800) // Apr 1, 2026 12:00 UTC

    /// The stores opencode leaves: one 1 wrote, one 2 started, one upgraded.
    nonisolated static let stores: [Set<Place>] = [[.message], [.sessionMessage], [.message, .sessionMessage]]

    /// A home whose opencode store holds `places` and `messages`; a home with
    /// no database at all when `places` is `nil`.
    private func home(_ places: Set<Place>?, _ messages: [OpenCodeStore.Message] = []) throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        if let places {
            try OpenCodeStore.make(at: home.appendingPathComponent("data/opencode/opencode.db"), places: places, messages)
        }
        return home
    }

    /// A provider whose default login has `key`, reading the store under
    /// `home` (one with no database when nil).
    private func make(body: String = usage, status: Int = 200, key: String? = "personal",
                      home: URL? = nil, clock: Date = now, available: Bool = true,
                      vault: MemoryVault = MemoryVault()) throws -> Provider {
        let home = try home ?? self.home(nil)
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

    @Test func `should show the 5-hour, weekly and monthly quotas with their resets and windows when OpenCode Go answers`() async throws {
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
    @Test(arguments:[("rolling","\"12.5\"",87.5),("weekly","130",0.0),("monthly","-4",100.0)])
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

    /// Go spend `seconds` before now, in `place` — the query works its
    /// windows out of SQLite's own `'now'`, so a fixed date would fall out of
    /// them. The exact windows are the SQL-level tests' to pin.
    private static func spent(_ id: String, _ seconds: TimeInterval, _ cost: Double, in place: Place,
                              provider: String = "opencode-go") -> OpenCodeStore.Message {
        OpenCodeStore.Message(id: id, at: Int64((Date() - seconds).timeIntervalSince1970 * 1000), provider: provider, cost: cost, place: place)
    }

    /// The spend of the local tests, in the places `store` has: the month's
    /// anchor long ago (in 1's place, when the store kept it), and every
    /// window's spend a minute ago.
    private static func spend(in store: Set<Place>) -> [OpenCodeStore.Message] {
        let past: Place = store.contains(.message) ? .message : .sessionMessage
        let present: Place = store.contains(.sessionMessage) ? .sessionMessage : .message
        return [
            spent("anchor", 400 * 86_400, 1.0, in: past),   // the first message: the month's anchor
            spent("a", 60, 0.5, in: past),                  // inside every window
            spent("b", 30, 0.25, in: present),
            spent("c", 20, 99, in: present, provider: "another"), // not OpenCode Go's
        ]
    }

    @Test(arguments: stores)
    func `should show dollars left of each cap from opencode's own database when there is no key`(_ store: Set<Place>) async throws {
        let p = try make(key:nil, home:home(store, Self.spend(in: store)))
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
    @Test func `should count a message an upgraded store holds in both places once`() async throws {
        let store: Set<Place> = [.message, .sessionMessage]
        let qs = try await make(key:nil, home:home(store, [Self.spent("same", 60, 2.0, in: .message),
                                                           Self.spent("same", 60, 2.0, in: .sessionMessage)])).refreshPlain().quotas
        #expect(qs[0].left == .money(Money(Decimal(string: "10.00")!, currency: "USD"), of: Money(12, currency: "USD")))
    }
    @Test(arguments: stores)
    func `should show every cap full and no monthly window when nothing has been spent yet`(_ store: Set<Place>) async throws {
        let qs = try await make(key:nil, home:home(store)).refreshPlain().quotas
        #expect(qs.map(\.percentLeft) == [100,100,100])
        #expect(abs(qs[0].resetsAt!.timeIntervalSince(Date()) - 18000) < 60) // now + 5h, by SQLite's clock
        #expect(qs[2].resetsAt == nil)
        #expect(qs[2].window?.length == nil)
    }
    @Test(arguments:[-5.0,6.0,20.0]) func `should never show less than nothing left of a cap`(_ cost:Double) async throws {
        let qs = try await make(key:nil, home:home([.sessionMessage], [Self.spent("a", 60, cost, in: .sessionMessage)])).refreshPlain().quotas
        #expect(qs[0].dollarRemaining == Decimal(string: String(format: "%.2f", max(0, 12 - cost))))
    }
    @Test func `should skip OpenCode Go and fail, never show usage, when there is no database`() async throws {
        let p = try make(key:nil)
        #expect(!(await p.isPlainAvailable()))
        await #expect(throws:UsageError.self) { try await p.refreshPlain() }
    }
    @Test func `should skip OpenCode Go when opencode's database keeps no messages it knows`() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try SQLiteFiles.make(at: home.appendingPathComponent("data/opencode/opencode.db"), "CREATE TABLE other(id TEXT);")
        let p = try make(key:nil, home:home)
        #expect(!(await p.isPlainAvailable()))
        await #expect(throws:UsageError.self) { try await p.refreshPlain() }
    }
    @Test func `should answer from the database alone when there is no key and no CLI`() async throws {
        // The database is read directly: the CLI's own query door came and
        // went with opencode 2 (#566), so the local mode never needs it.
        let p = try make(key:nil, home:home([.sessionMessage]), available:false)
        #expect(await p.isPlainAvailable())
        let qs = try await p.refreshPlain().quotas
        #expect(qs.map(\.quotaType) == [.session,.weekly,.timeLimit("Monthly")])
    }

    // MARK: - The queries themselves, run by SQLite

    /// The local call's queries, in order: both places, 2's, 1's.
    nonisolated private static let queries = Array(0..<3)

    /// The `index`th of the local call's queries against a store holding the
    /// tables it requires, as of `now` (UTC). In a store with both places
    /// the first message (the month's anchor) is 1's, the rest 2's.
    private func query(_ index: Int, _ messages: [(at: String, cost: Double, provider: String)], now: String) throws -> [String: Any] {
        let definition = try ProviderFactory.builtIn("opencode-go")
        guard case .sqlite(let call) = try #require(definition.dataSource("local")).fetch else {
            Issue.record("Expected the local source to read the database itself"); return [:]
        }
        let query = call.queries[index]
        let places = Set(query.requires.compactMap(Place.init(rawValue:)))
        let formatter = ISO8601DateFormatter()
        let stored = try messages.enumerated().map { n, message in
            OpenCodeStore.Message(id: "msg_\(n)", at: Int64(try #require(formatter.date(from: message.at)).timeIntervalSince1970 * 1000),
                                  provider: message.provider, cost: message.cost,
                                  place: places.count == 2 ? (n == 0 ? .message : .sessionMessage) : places.first!)
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = root.appendingPathComponent("opencode.db")
        try OpenCodeStore.make(at: db, places: places, stored)
        return try #require(try SQLiteFiles.rows(at: db, query.query.replacingOccurrences(of: "'now'", with: "'\(now)'")).first)
    }

    private func ms(_ text: String) throws -> Int64 {
        Int64(try #require(ISO8601DateFormatter().date(from: text)).timeIntervalSince1970 * 1000)
    }

    @Test func `should read the store with the first query whose tables it has: both places, 2's, then 1's`() throws {
        let definition = try ProviderFactory.builtIn("opencode-go")
        guard case .sqlite(let call) = try #require(definition.dataSource("local")).fetch else {
            Issue.record("Expected the local source to read the database itself"); return
        }
        #expect(call.queries.map(\.requires) == [["message", "session_message"], ["session_message"], ["message"]])
    }

    @Test(arguments: queries) func `should add up the last 5 hours, the UTC week and the anchored month of OpenCode Go spend only`(_ index: Int) throws {
        let row = try query(index, [
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

    @Test(arguments: queries.flatMap { index in
        [
            ("2024-03-14T14:30:00Z", "2024-04-02 10:00:00", "2024-04-14T14:30:00Z", index),
            ("2024-01-20T09:00:00Z", "2024-04-05 12:00:00", "2024-04-20T09:00:00Z", index),
            // The 31st in a 29-day February: the month ends on its last day.
            ("2024-01-31T09:00:00Z", "2024-02-05 12:00:00", "2024-02-29T09:00:00Z", index),
        ]
    })
    func `should start each month on the first message's day, or the month's last day when it is shorter`(_ fixture: (String, String, String, Int)) throws {
        let row = try query(fixture.3, [(fixture.0, 1, "opencode-go")], now: fixture.1)
        #expect(row["month_end_ms"] as? Int64 == (try ms(fixture.2)))
    }

    @Test(arguments: queries) func `should show no spend and no month when there are no OpenCode Go messages`(_ index: Int) throws {
        let row = try query(index, [("2026-05-04T14:00:00Z", 5, "another")], now: "2026-05-04 15:00:00")
        #expect(row["five_hour_cost"] as? Double == 0)
        #expect(row["monthly_cost"] as? Double == 0)
        #expect(row["month_start_ms"] == nil || row["month_start_ms"] is NSNull)
    }

    @Test func `should use only an added login's own key, never the local database, and ask to sign in when it is gone`() async throws {
        let vault = MemoryVault()
        let p = try make(vault:vault)
        let work = try p.accounts.add(filling:["apiKey":"work"])
        #expect(p.dataSources(for:work).map(\.kind) == ["api"])
        #expect(try await p.refresh(work).quotas.map(\.percentRemaining) == [99,83,0])
        vault.secrets["\(work.id).apiKey"] = nil
        await #expect(throws:UsageError.authenticationRequired) { try await p.refresh(work) }
    }
    @Test(arguments:["opencode-go","opencode","both"])
    func `should use the key opencode saved in its auth file under XDG_DATA_HOME`(_ entry:String) async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:home) }
        let data = home.appendingPathComponent("data/opencode")
        try FileManager.default.createDirectory(at:data,withIntermediateDirectories:true)
        let auth = entry == "both" ? #"{"opencode-go":{"key":"file-key"},"opencode":{"key":"other-key"}}"# : "{\"\(entry)\":{\"type\":\"api\",\"key\":\"file-key\"}}"
        try Data(auth.utf8).write(to:data.appendingPathComponent("auth.json"))
        let p = try make(key:nil, home:home)
        #expect(try await p.refreshPlain().quotas.map(\.percentRemaining) == [99,83,0])
    }
}
