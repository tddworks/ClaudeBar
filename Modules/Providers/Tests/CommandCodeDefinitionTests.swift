import Testing
import Foundation
import Mockable
import Providers
import DataSources
import Quotas

/// Command Code as data: `whoami`, then `credits` with the org it named,
/// read by `commandcode-credits.js` — the old probe's fixtures, quota for quota.
@MainActor @Suite
struct CommandCodeDefinitionTests {

    /// Real credits body from `GET /alpha/billing/credits`.
    static let sampleResponse = """
    {
      "credits": {
        "monthlyCredits": 8.5,
        "purchasedCredits": 0,
        "freeCredits": 0,
        "planId": "individual-go"
      },
      "windowLimits": {
        "fiveHour": { "used": 10, "cap": 40, "resetAt": 1770000000000 },
        "weekly": { "used": 50, "cap": 200, "resetAt": 1770500000000 }
      }
    }
    """

    private func make(_ json: String = sampleResponse, whoami: String = #"{"user":{"userName":"alice"},"org":{"id":42}}"#,
                      status: Int = 200, creditsStatus: Int? = nil, networkFailure: Bool = false, acceptedTokens: [String] = ["personal", "work", "file"], vault: MemoryVault = MemoryVault(["commandcode.apiKey":"personal"]),
                      environment: [String:String] = [:], home: URL = FileManager.default.temporaryDirectory) throws -> Provider {
        let definition = try Providers.builtIn("commandcode")
        let first = (try? JSONSerialization.jsonObject(with:Data(whoami.utf8))) as? [String:Any] ?? [:]
        let payload = first["data"] as? [String:Any] ?? first
        let expectedOrg = ((payload["org"] as? [String:Any])?["id"]).map { String(describing:$0) }
        let network = MockNetworkClient()
        given(network).request(.any).willProduce { @Sendable request in
            #expect(request.url?.host == "api.commandcode.ai")
            #expect(request.timeoutInterval == 15)
            #expect(acceptedTokens.map { "Bearer " + $0 }.contains(request.value(forHTTPHeaderField:"Authorization") ?? ""))
            if networkFailure { throw URLError(.notConnectedToInternet) }
            let first = request.url?.path == "/alpha/whoami"
            if !first {
                let query = URLComponents(url:request.url!,resolvingAgainstBaseURL:false)?.queryItems?.first(where:{$0.name == "orgId"})?.value
                #expect(query == expectedOrg)
            }
            return (Data((first ? whoami : json).utf8),HTTPURLResponse(url:request.url!,statusCode:first ? status : (creditsStatus ?? status),httpVersion:nil,headerFields:nil)!)
        }
        return Provider(definition:definition,settings:InMemoryProviderSettings(),makeDataSource:{source,login in
            DataSources.make(source,providerId:definition.id,cliExecutor:MockCLIExecutor(),network:network,
                makeTransport:{_,_,_,_ in MockRPCTransport()},scripts:Providers.builtInScripts,secrets:vault.scoped(to:login),
                environment:{environment[$0]},homeDirectory:home,now:{Date()})
        },vault:vault)
    }
    private func parse(_ json: String, accountEmail: String? = nil) async throws -> UsageSnapshot {
        let user = try JSONSerialization.data(withJSONObject:["user":["userName":accountEmail ?? ""],"org":["id":42]])
        return try await make(json,whoami:String(decoding:user,as:UTF8.self)).defaultAccount.refresh()
    }

    @Test
    func `parses provider id`() async throws {
        #expect(try await parse(Self.sampleResponse).providerId == "commandcode")
    }

    @Test
    func `maps five hour window to session quota`() async throws {
        let session = try #require(try await parse(Self.sampleResponse).quota(for: .session))

        #expect(session.percentRemaining == 75)
        #expect(session.resetsAt == Date(timeIntervalSince1970: 1_770_000_000))
        #expect(session.windowDuration == TimeInterval(5 * 3600))
    }

    @Test
    func `maps weekly window to weekly quota`() async throws {
        let weekly = try #require(try await parse(Self.sampleResponse).quota(for: .weekly))

        #expect(weekly.percentRemaining == 75)
        #expect(weekly.resetsAt == Date(timeIntervalSince1970: 1_770_500_000))
        #expect(weekly.windowDuration == TimeInterval(7 * 24 * 3600))
    }

    @Test
    func `maps plan allowance to a credits meter`() async throws {
        let credits = try #require(try await parse(Self.sampleResponse).quota(for: .timeLimit("Credits")))

        #expect(credits.left == .money(Money(Decimal(string: "8.5")!, currency: "USD"), of: Money(10, currency: "USD")))
        #expect(credits.percentRemaining == 85) // 8.5 of 10
        #expect(credits.dollarRemaining == 8.5)
        #expect(credits.dollarUsed == 1.5)
        #expect(credits.dollarCap == 10)
    }

    @Test
    func `passes account email through`() async throws {
        let snapshot = try await parse(Self.sampleResponse, accountEmail: "alice@example.com")

        #expect(snapshot.accountEmail == "alice@example.com")
    }

    @Test
    func `unwraps a data envelope`() async throws {
        let json = """
        { "data": \(Self.sampleResponse) }
        """

        let snapshot = try await parse(json)

        #expect(snapshot.quota(for: .session)?.percentRemaining == 75)
        #expect(snapshot.quota(for: .timeLimit("Credits"))?.dollarRemaining == 8.5)
    }

    @Test
    func `returns empty snapshot for empty object`() async throws {
        #expect(try await parse("{}").quotas.isEmpty)
    }

    @Test
    func `throws parseFailed on invalid JSON`() async {
        await #expect(throws: UsageError.self) { try await parse("not json") }
    }

    @Test
    func `skips a window with zero cap`() async throws {
        let json = """
        {
          "windowLimits": {
            "fiveHour": { "used": 0, "cap": 0, "resetAt": 1770000000000 },
            "weekly": { "used": 50, "cap": 200, "resetAt": 1770500000000 }
          }
        }
        """

        let snapshot = try await parse(json)

        #expect(snapshot.quota(for: .session) == nil)
        #expect(snapshot.quota(for: .weekly)?.percentRemaining == 75)
    }

    @Test
    func `treats missing used as zero`() async throws {
        let json = """
        { "windowLimits": { "fiveHour": { "cap": 40, "resetAt": 1770000000000 } } }
        """

        #expect(try await parse(json).quota(for: .session)?.percentRemaining == 100)
    }

    @Test
    func `parses ISO-8601 reset timestamp`() async throws {
        let json = """
        { "windowLimits": { "fiveHour": { "used": 10, "cap": 40, "resetAt": "2026-09-11T12:00:00Z" } } }
        """

        let session = try #require(try await parse(json).quota(for: .session))

        #expect(session.resetsAt == Date(timeIntervalSince1970: 1_789_128_000))
    }

    @Test
    func `parses epoch-second reset timestamp`() async throws {
        let json = """
        { "windowLimits": { "fiveHour": { "used": 10, "cap": 40, "resetAt": 1770000000 } } }
        """

        let session = try #require(try await parse(json).quota(for: .session))

        #expect(session.resetsAt == Date(timeIntervalSince1970: 1_770_000_000))
    }

    @Test
    func `prefers the longest matching plan id`() async throws {
        // individual-pro-v1 ($80) must not match individual-pro ($30)
        let json = """
        { "credits": { "monthlyCredits": 80, "purchasedCredits": 0, "freeCredits": 0, "planId": "individual-pro-v1" } }
        """

        let credits = try #require(try await parse(json).quota(for: .timeLimit("Credits")))

        #expect(credits.percentRemaining == 100)
        #expect(credits.dollarCap == 80)
    }

    @Test
    func `normalizes underscores and case in plan id`() async throws {
        let json = """
        { "credits": { "monthlyCredits": 4, "purchasedCredits": 0, "freeCredits": 0, "planId": "Teams_Pro" } }
        """

        let credits = try #require(try await parse(json).quota(for: .timeLimit("Credits")))

        #expect(credits.percentRemaining == 10) // 4 of 40
        #expect(credits.dollarCap == 40)
    }

    @Test
    func `adds purchased and free credits to the allowance`() async throws {
        let json = """
        {
          "credits": {
            "monthlyCredits": 2, "purchasedCredits": 20, "freeCredits": 3, "planId": "individual-go"
          }
        }
        """

        let credits = try #require(try await parse(json).quota(for: .timeLimit("Credits")))

        #expect(credits.dollarRemaining == 25)
        #expect(credits.dollarCap == 33) // plan 10 + purchased 20 + free 3
    }

    @Test
    func `shows a balance-only meter for an unknown plan with no windows`() async throws {
        let json = """
        { "credits": { "monthlyCredits": 12.5, "purchasedCredits": 0, "freeCredits": 0, "planId": "mystery-tier" } }
        """

        let credits = try #require(try await parse(json).quota(for: .timeLimit("Credits")))

        // A balance with no ceiling is money only — no percentage (the Left law).
        #expect(credits.left == .money(Money(Decimal(string: "12.5")!, currency: "USD"), of: nil))
        #expect(credits.percentLeft == nil)
        #expect(credits.dollarRemaining == 12.5)
        #expect(credits.dollarCap == nil)
    }

    @Test
    func `skips a balance-only meter when windows already report usage`() async throws {
        let json = """
        {
          "credits": { "monthlyCredits": 12.5, "planId": "mystery-tier" },
          "windowLimits": { "weekly": { "used": 50, "cap": 200, "resetAt": 1770500000000 } }
        }
        """

        let snapshot = try await parse(json)

        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quota(for: .weekly) != nil)
    }

    @Test
    func `reports zero remaining when the plan allowance is exhausted`() async throws {
        let json = """
        { "credits": { "monthlyCredits": 0, "purchasedCredits": 0, "freeCredits": 0, "planId": "individual-go" } }
        """

        let snapshot = try await parse(json)

        #expect(snapshot.quota(for: .timeLimit("Credits"))?.percentRemaining == 0)
    }

    @Test
    func `reports over-cap windows as negative remaining`() async throws {
        let json = """
        { "windowLimits": { "fiveHour": { "used": 44, "cap": 40, "resetAt": 1770000000000 } } }
        """

        #expect(try await parse(json).quota(for: .session)?.percentRemaining == -10)
    }
    @Test func `account key is isolated from the default environment`() async throws {
        let vault = MemoryVault(["commandcode.apiKey":"personal"])
        let provider = try make(vault:vault,environment:["COMMAND_CODE_API_KEY":"personal"])
        let work = try provider.addAccount(filling:["apiKey":"work"])
        #expect(work.isEnabled)
        #expect(try await work.refresh().accountEmail == "alice")
        vault.secrets["\(work.id).apiKey"] = nil
        await #expect(throws:UsageError.authenticationRequired) { try await work.refresh() }
    }
    @Test(arguments:[401,403]) func `rejected keys preserve the login hint`(_ status:Int) async throws {
        await #expect(throws:UsageError.sessionExpired(hint:"Run `cmd login` or set COMMAND_CODE_API_KEY.")) {
            try await make(status:status).defaultAccount.refresh()
        }
    }
    @Test func `saved CLI credentials remain readable`() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:home) }
        let dir = home.appendingPathComponent(".commandcode")
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        try Data(#"{"apiKey":"file"}"#.utf8).write(to:dir.appendingPathComponent("auth.json"))
        #expect(try await make(vault:MemoryVault(),home:home).defaultAccount.refresh().quotas.count == 3)
    }

    @Test(arguments:["{}",#"{"data":{"user":{"name":"Alice"},"org":{"id":"team & org"}}}"#])
    func `missing organization and wrapped organization queries remain valid`(_ whoami:String) async throws {
        #expect(try await make(whoami:whoami).defaultAccount.refresh().quotas.count == 3)
    }

    @Test(arguments: [
        (#"{"apiKey":"file"}"#, ["COMMAND_CODE_API_KEY":"personal", "COMMANDCODE_API_KEY":"work"], true),
        (#"{"apiKey":"file"}"#, ["COMMANDCODE_API_KEY":"work"], true),
        (#"{"apiKey":"  file\n"}"#, [:], true),
        (#"{"apiKey":"   "}"#, [:], false),
        (#"["file"]"#, [:], false),
        ("not JSON", [:], false),
        ("", [:], false)
    ])
    func `legacy credential fixtures preserve precedence and availability`(_ file: String, _ environment: [String:String], _ available: Bool) async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let directory = home.appendingPathComponent(".commandcode")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !file.isEmpty { try Data(file.utf8).write(to: directory.appendingPathComponent("auth.json")) }
        let token = environment["COMMAND_CODE_API_KEY"] ?? environment["COMMANDCODE_API_KEY"] ?? "file"
        let provider = try make(acceptedTokens: [token], vault: MemoryVault(), environment: environment, home: home)
        #expect(await provider.defaultAccount.isAvailable() == available)
        if available { #expect(try await provider.defaultAccount.refresh().quotas.count == 3) }
        else { await #expect(throws: UsageError.authenticationRequired) { try await provider.defaultAccount.refresh() } }
    }

    @Test func `definition preserves identity and initial state`() throws {
        let provider = try make().defaultAccount
        #expect(provider.id == "commandcode")
        #expect(provider.name == "Command Code")
        #expect(provider.cliCommand == "cmd")
        #expect(provider.dashboardURL?.absoluteString == "https://commandcode.ai/usage")
        #expect(provider.isEnabled)
        #expect(provider.snapshot == nil)
        #expect(provider.lastError == nil)
        #expect(!provider.isSyncing)
    }

    @Test(arguments: [401,403,500])
    func `credits errors keep the legacy failure instead of accepting identity alone`(_ status: Int) async throws {
        let error: UsageError = [401,403].contains(status)
            ? .sessionExpired(hint: "Run `cmd login` or set COMMAND_CODE_API_KEY.")
            : .executionFailed("HTTP error: \(status)")
        let account = try make(creditsStatus: status).defaultAccount
        await #expect(throws: error) { try await account.refresh() }
        #expect(account.snapshot == nil)
        #expect(account.lastError as? UsageError == error)
    }
    @Test func `a rate limit on credits is remembered, not reported as an HTTP error`() async throws {
        let account = try make(creditsStatus: 429).defaultAccount
        await #expect { try await account.refresh() } throws: { ($0 as? UsageError)?.tag == "rateLimited" }
        #expect(account.snapshot == nil)
    }

    @Test func `network failure cannot become a successful snapshot`() async throws {
        let account = try make(networkFailure: true).defaultAccount
        await #expect(throws: UsageError.self) { try await account.refresh() }
        #expect(account.snapshot == nil)
    }
    @Test(arguments: ["[]", "not JSON"])
    func `both responses must be JSON objects`(_ body: String) async throws {
        await #expect(throws: UsageError.parseFailed("Failed to parse Command Code response as JSON")) {
            try await make(body).defaultAccount.refresh()
        }
        await #expect(throws: UsageError.parseFailed("Failed to parse Command Code response as JSON")) {
            try await make(whoami: body).defaultAccount.refresh()
        }
    }

}
