import Testing
import Foundation
import Mockable
import Providers
import DataSources
import Quotas
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Command Code as data: `whoami`, `credits`, optional `subscriptions`, and optional `summary`,
/// read by `commandcode-credits.js`.
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
                      subscriptions: String = "{}", summary: String = "{}",
                      status: Int = 200, creditsStatus: Int? = nil, subscriptionsStatus: Int = 200, summaryStatus: Int = 200,
                      networkFailure: Bool = false, acceptedTokens: [String] = ["personal", "work", "file"],
                      vault: MemoryVault = MemoryVault(["commandcode.apiKey":"personal"]),
                      environment: [String:String] = [:], home: URL = FileManager.default.temporaryDirectory) throws -> Provider {
        let definition = try ProviderFactory.builtIn("commandcode")
        let first = (try? JSONSerialization.jsonObject(with:Data(whoami.utf8))) as? [String:Any] ?? [:]
        let payload = first["data"] as? [String:Any] ?? first
        let expectedOrg = ((payload["org"] as? [String:Any])?["id"]).map { String(describing:$0) }
        let subRoot = (try? JSONSerialization.jsonObject(with:Data(subscriptions.utf8))) as? [String:Any] ?? [:]
        let subPayload = subRoot["data"] as? [String:Any] ?? subRoot
        let expectedSince = subPayload["currentPeriodStart"] as? String
        let network = MockNetworkClient()
        given(network).request(.any).willProduce { @Sendable request in
            #expect(request.url?.host == "api.commandcode.ai")
            #expect(request.timeoutInterval == 15)
            #expect(acceptedTokens.map { "Bearer " + $0 }.contains(request.value(forHTTPHeaderField:"Authorization") ?? ""))
            if networkFailure { throw URLError(.notConnectedToInternet) }
            let path = request.url?.path
            let queryItems = URLComponents(url:request.url!,resolvingAgainstBaseURL:false)?.queryItems ?? []
            if path != "/alpha/whoami" {
                let query = queryItems.first(where:{$0.name == "orgId"})?.value
                #expect(query == expectedOrg)
            }
            switch path {
            case "/alpha/whoami":
                return (Data(whoami.utf8),HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:nil)!)
            case "/alpha/billing/credits":
                return (Data(json.utf8),HTTPURLResponse(url:request.url!,statusCode:creditsStatus ?? status,httpVersion:nil,headerFields:nil)!)
            case "/alpha/billing/subscriptions":
                return (Data(subscriptions.utf8),HTTPURLResponse(url:request.url!,statusCode:subscriptionsStatus,httpVersion:nil,headerFields:nil)!)
            case "/alpha/usage/summary":
                let since = queryItems.first(where:{$0.name == "since"})?.value
                #expect(since == expectedSince)
                return (Data(summary.utf8),HTTPURLResponse(url:request.url!,statusCode:summaryStatus,httpVersion:nil,headerFields:nil)!)
            default:
                Issue.record("Unexpected path: \(path ?? "<nil>")")
                return (Data("{}".utf8),HTTPURLResponse(url:request.url!,statusCode:404,httpVersion:nil,headerFields:nil)!)
            }
        }
        return Provider(definition:definition,settings:InMemoryProviderSettings(),makeDataSource:{source,login in
            DataSources.make(source,providerId:definition.id,cliExecutor:MockCLIExecutor(),network:network,
                makeTransport:{_,_,_,_ in MockRPCTransport()},scripts:ProviderFactory.builtInScripts,secrets:vault.scoped(to:login),
                environment:{environment[$0]},homeDirectory:home,now:{Date()})
        },vault:vault)
    }
    private func parse(_ json: String, accountEmail: String? = nil, subscriptions: String = "{}", summary: String = "{}") async throws -> UsageSnapshot {
        let user = try JSONSerialization.data(withJSONObject:["user":["userName":accountEmail ?? ""],"org":["id":42]])
        return try await make(json,whoami:String(decoding:user,as:UTF8.self),subscriptions:subscriptions,summary:summary).refreshPlain()
    }

    @Test
    func `should show the monthly credits from subscriptions when credits omits planId`() async throws {
        let creditsJson = """
        {
          "credits": {
            "belowThreshold": false,
            "creditThreshold": 0,
            "monthlyCredits": 0.1,
            "purchasedCredits": 0,
            "freeCredits": 0
          },
          "windowLimits": {
            "limited": true,
            "fiveHour": { "used": 0.4, "cap": 3, "resetAt": 1794653072303 },
            "weekly": { "used": 0.6, "cap": 6, "resetAt": 1795174633785 }
          }
        }
        """
        let subscriptionsJson = """
        {
          "success": true,
          "data": {
            "status": "active",
            "planId": "individual-go-v1",
            "currentPeriodStart": "2026-10-25T09:28:05.000Z",
            "currentPeriodEnd": "2026-11-25T09:28:05.000Z"
          }
        }
        """

        let snapshot = try await parse(creditsJson, subscriptions: subscriptionsJson)

        #expect(snapshot.quotas.count == 3)
        let credits = try #require(snapshot.quota(for: .timeLimit("Credits")))
        #expect(credits.left == .money(Money(Decimal(string: "0.1")!, currency: "USD"), of: Money(10, currency: "USD")))
        #expect(credits.percentRemaining == 1)
        #expect(credits.resetsAt == Date(timeIntervalSince1970: 1_795_598_885))
        #expect(credits.windowDuration == TimeInterval(31 * 86400))
    }

    @Test
    func `should fall back to usage summary and remaining credits when the active plan is unknown`() async throws {
        let creditsJson = """
        {
          "credits": { "monthlyCredits": 7.5, "purchasedCredits": 0, "freeCredits": 0 },
          "windowLimits": {
            "fiveHour": { "used": 1, "cap": 4, "resetAt": 1794653072303 }
          }
        }
        """
        let subscriptionsJson = """
        {
          "data": {
            "status": "active",
            "planId": "enterprise-custom",
            "currentPeriodStart": "2026-10-25T09:28:05.000Z",
            "currentPeriodEnd": "2026-11-25T09:28:05.000Z"
          }
        }
        """
        let summaryJson = #"{ "totalCost": 22.5 }"#

        let snapshot = try await parse(creditsJson, subscriptions: subscriptionsJson, summary: summaryJson)

        #expect(snapshot.quotas.count == 2)
        let credits = try #require(snapshot.quota(for: .timeLimit("Credits")))
        #expect(credits.left == .money(Money(Decimal(string: "7.5")!, currency: "USD"), of: Money(30, currency: "USD")))
        #expect(credits.percentRemaining == 25)
        #expect(credits.resetsAt == Date(timeIntervalSince1970: 1_795_598_885))
        #expect(credits.windowDuration == TimeInterval(31 * 86400))
    }

    @Test(arguments: [404, 500])
    func `should still show window limits when subscriptions or summary fails`(_ status: Int) async throws {
        let creditsJson = """
        {
          "credits": { "monthlyCredits": 4, "purchasedCredits": 0, "freeCredits": 0 },
          "windowLimits": {
            "fiveHour": { "used": 10, "cap": 40, "resetAt": 1770000000000 },
            "weekly": { "used": 50, "cap": 200, "resetAt": 1770500000000 }
          }
        }
        """

        let snapshot = try await make(creditsJson, subscriptionsStatus: status, summaryStatus: status).refreshPlain()

        #expect(snapshot.quotas.count == 2)
        #expect(snapshot.quota(for: .session)?.percentRemaining == 75)
        #expect(snapshot.quota(for: .weekly)?.percentRemaining == 75)
    }

    @Test
    func `should ignore monthly plan allowance and period reset when the subscription is canceled`() async throws {
        let creditsJson = """
        {
          "credits": { "monthlyCredits": 0, "purchasedCredits": 5, "freeCredits": 0, "planId": "individual-go-v1" }
        }
        """
        let subscriptionsJson = """
        {
          "data": {
            "status": "canceled",
            "planId": "individual-go-v1",
            "currentPeriodStart": "2026-09-25T09:28:05.000Z",
            "currentPeriodEnd": "2026-10-25T09:28:05.000Z"
          }
        }
        """
        let summaryJson = #"{ "totalCost": 15 }"#

        let credits = try #require(try await parse(creditsJson, subscriptions: subscriptionsJson, summary: summaryJson).quota(for: .timeLimit("Credits")))

        #expect(credits.left == .money(Money(5, currency: "USD"), of: nil))
        #expect(credits.dollarCap == nil)
        #expect(credits.resetsAt == nil)
        #expect(credits.windowDuration == nil)
    }

    @Test(arguments: [(401, "sessionExpired"), (429, "rateLimited")])
    func `should ask to sign in again or wait when subscriptions is refused or rate limited`(_ status: Int, _ tag: String) async throws {
        let product = try make(subscriptionsStatus: status)
        let account = product.defaultAccount

        await #expect { try await product.refresh(account) } throws: { ($0 as? UsageError)?.tag == tag }
        #expect(account.snapshot == nil)
    }

    @Test
    func `should file the usage under Command Code`() async throws {
        #expect(try await parse(Self.sampleResponse).providerId == "commandcode")
    }

    @Test
    func `should show the five-hour window as the session, with its reset`() async throws {
        let session = try #require(try await parse(Self.sampleResponse).quota(for: .session))

        #expect(session.percentRemaining == 75)
        #expect(session.resetsAt == Date(timeIntervalSince1970: 1_770_000_000))
        #expect(session.windowDuration == TimeInterval(5 * 3600))
    }

    @Test
    func `should show the weekly window with its reset`() async throws {
        let weekly = try #require(try await parse(Self.sampleResponse).quota(for: .weekly))

        #expect(weekly.percentRemaining == 75)
        #expect(weekly.resetsAt == Date(timeIntervalSince1970: 1_770_500_000))
        #expect(weekly.windowDuration == TimeInterval(7 * 24 * 3600))
    }

    @Test
    func `should show the plan's credits left in dollars out of its allowance`() async throws {
        let credits = try #require(try await parse(Self.sampleResponse).quota(for: .timeLimit("Credits")))

        #expect(credits.left == .money(Money(Decimal(string: "8.5")!, currency: "USD"), of: Money(10, currency: "USD")))
        #expect(credits.percentRemaining == 85) // 8.5 of 10
        #expect(credits.dollarRemaining == 8.5)
        #expect(credits.dollarUsed == 1.5)
        #expect(credits.dollarCap == 10)
    }

    @Test
    func `should show the account's user name`() async throws {
        let snapshot = try await parse(Self.sampleResponse, accountEmail: "alice@example.com")

        #expect(snapshot.accountEmail == "alice@example.com")
    }

    @Test
    func `should show the usage when Command Code wraps it in a data envelope`() async throws {
        let json = """
        { "data": \(Self.sampleResponse) }
        """

        let snapshot = try await parse(json)

        #expect(snapshot.quota(for: .session)?.percentRemaining == 75)
        #expect(snapshot.quota(for: .timeLimit("Credits"))?.dollarRemaining == 8.5)
    }

    @Test
    func `should show no quotas when Command Code reports nothing`() async throws {
        #expect(try await parse("{}").quotas.isEmpty)
    }

    @Test
    func `should fail when Command Code answers with something that isn't JSON`() async {
        await #expect(throws: UsageError.self) { try await parse("not json") }
    }

    @Test
    func `should show no window whose cap is zero`() async throws {
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
    func `should show a window full when Command Code omits how much is used`() async throws {
        let json = """
        { "windowLimits": { "fiveHour": { "cap": 40, "resetAt": 1770000000000 } } }
        """

        #expect(try await parse(json).quota(for: .session)?.percentRemaining == 100)
    }

    @Test
    func `should know the reset when it is a date string`() async throws {
        let json = """
        { "windowLimits": { "fiveHour": { "used": 10, "cap": 40, "resetAt": "2026-09-11T12:00:00Z" } } }
        """

        let session = try #require(try await parse(json).quota(for: .session))

        #expect(session.resetsAt == Date(timeIntervalSince1970: 1_789_128_000))
    }

    @Test
    func `should know the reset when it is in seconds`() async throws {
        let json = """
        { "windowLimits": { "fiveHour": { "used": 10, "cap": 40, "resetAt": 1770000000 } } }
        """

        let session = try #require(try await parse(json).quota(for: .session))

        #expect(session.resetsAt == Date(timeIntervalSince1970: 1_770_000_000))
    }

    @Test(arguments: ["1770000000000", "1770000000"])
    func `should know the reset when it is a numeric string`(_ resetAt: String) async throws {
        let json = """
        { "windowLimits": { "fiveHour": { "used": 10, "cap": 40, "resetAt": "\(resetAt)" } } }
        """

        let session = try #require(try await parse(json).quota(for: .session))

        #expect(session.resetsAt == Date(timeIntervalSince1970: 1_770_000_000))
    }

    @Test
    func `should size the credits by the most specific plan name`() async throws {
        // individual-pro-v1 ($80) must not match individual-pro ($30)
        let json = """
        { "credits": { "monthlyCredits": 80, "purchasedCredits": 0, "freeCredits": 0, "planId": "individual-pro-v1" } }
        """

        let credits = try #require(try await parse(json).quota(for: .timeLimit("Credits")))

        #expect(credits.percentRemaining == 100)
        #expect(credits.dollarCap == 80)
    }

    @Test
    func `should recognise a plan whatever its case or underscores`() async throws {
        let json = """
        { "credits": { "monthlyCredits": 4, "purchasedCredits": 0, "freeCredits": 0, "planId": "Teams_Pro" } }
        """

        let credits = try #require(try await parse(json).quota(for: .timeLimit("Credits")))

        #expect(credits.percentRemaining == 10) // 4 of 40
        #expect(credits.dollarCap == 40)
    }

    @Test
    func `should add purchased and free credits to the plan's allowance`() async throws {
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
    func `should show only the dollars left, with no percentage, for an unknown plan with no windows`() async throws {
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
    func `should show no balance meter when windows already report usage`() async throws {
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
    func `should show no credits left when the plan's allowance is spent`() async throws {
        let json = """
        { "credits": { "monthlyCredits": 0, "purchasedCredits": 0, "freeCredits": 0, "planId": "individual-go" } }
        """

        let snapshot = try await parse(json)

        #expect(snapshot.quota(for: .timeLimit("Credits"))?.percentRemaining == 0)
    }

    @Test
    func `should show a window past its cap as below zero`() async throws {
        let json = """
        { "windowLimits": { "fiveHour": { "used": 44, "cap": 40, "resetAt": 1770000000000 } } }
        """

        #expect(try await parse(json).quota(for: .session)?.percentRemaining == -10)
    }
    @Test func `should read an added login with its own key, never the environment's`() async throws {
        let vault = MemoryVault(["commandcode.apiKey":"personal"])
        let provider = try make(vault:vault,environment:["COMMAND_CODE_API_KEY":"personal"])
        let work = try provider.accounts.add(filling:["apiKey":"work"])
        #expect(!work.isPaused)
        #expect(try await provider.refresh(work).accountEmail == "alice")
        vault.secrets["\(work.id).apiKey"] = nil
        await #expect(throws:UsageError.authenticationRequired) { try await provider.refresh(work) }
    }
    @Test(arguments:[401,403]) func `should ask to sign in again with cmd login when the key is refused`(_ status:Int) async throws {
        await #expect(throws:UsageError.sessionExpired(hint:"Run `cmd login` or set COMMAND_CODE_API_KEY.")) {
            try await make(status:status).refreshPlain()
        }
    }
    @Test func `should read the key the Command Code CLI saved`() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:home) }
        let dir = home.appendingPathComponent(".commandcode")
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        try Data(#"{"apiKey":"file"}"#.utf8).write(to:dir.appendingPathComponent("auth.json"))
        #expect(try await make(vault:MemoryVault(),home:home).refreshPlain().quotas.count == 3)
    }

    @Test(arguments:["{}",#"{"data":{"user":{"name":"Alice"},"org":{"id":"team & org"}}}"#])
    func `should show the credits when the account names no organization or a wrapped one`(_ whoami:String) async throws {
        #expect(try await make(whoami:whoami).refreshPlain().quotas.count == 3)
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
    func `should prefer an environment key over the CLI's saved key, and be unavailable without a usable key`(_ file: String, _ environment: [String:String], _ available: Bool) async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let directory = home.appendingPathComponent(".commandcode")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !file.isEmpty { try Data(file.utf8).write(to: directory.appendingPathComponent("auth.json")) }
        let token = environment["COMMAND_CODE_API_KEY"] ?? environment["COMMANDCODE_API_KEY"] ?? "file"
        let provider = try make(acceptedTokens: [token], vault: MemoryVault(), environment: environment, home: home)
        #expect(await provider.isPlainAvailable() == available)
        if available { #expect(try await provider.refreshPlain().quotas.count == 3) }
        else { await #expect(throws: UsageError.authenticationRequired) { try await provider.refreshPlain() } }
    }

    @Test func `should start as Command Code, run by cmd, with its usage dashboard and nothing read yet`() throws {
        let providerProduct = try make()
        let provider = providerProduct.defaultAccount
        #expect(provider.id == "commandcode")
        #expect(providerProduct.lineupName(of: provider) == "Command Code")
        #expect(provider.cliCommand == "cmd")
        #expect(providerProduct.dashboardURL(of: provider)?.absoluteString == "https://commandcode.ai/usage")
        #expect(!provider.isPaused)
        #expect(provider.snapshot == nil)
        #expect(provider.lastError == nil)
        #expect(!provider.isSyncing)
    }

    @Test(arguments: [401,403,500])
    func `should fail, not show the account alone, when the credits request is refused or errors`(_ status: Int) async throws {
        let error: UsageError = [401,403].contains(status)
            ? .sessionExpired(hint: "Run `cmd login` or set COMMAND_CODE_API_KEY.")
            : .executionFailed("HTTP error: \(status)")
        let product = try make(creditsStatus: status)
        let account = product.defaultAccount
        await #expect(throws: error) { try await product.refresh(account) }
        #expect(account.snapshot == nil)
        #expect(account.lastError as? UsageError == error)
    }
    @Test func `should say it is rate limited, not an HTTP error, when the credits request is`() async throws {
        let product = try make(creditsStatus: 429)
        let account = product.defaultAccount
        await #expect { try await product.refresh(account) } throws: { ($0 as? UsageError)?.tag == "rateLimited" }
        #expect(account.snapshot == nil)
    }

    @Test func `should show no usage when the network fails`() async throws {
        let product = try make(networkFailure: true)
        let account = product.defaultAccount
        await #expect(throws: UsageError.self) { try await product.refresh(account) }
        #expect(account.snapshot == nil)
    }
    @Test(arguments: ["[]", "not JSON"])
    func `should fail when either answer is not a JSON object`(_ body: String) async throws {
        await #expect(throws: UsageError.parseFailed("Failed to parse Command Code response as JSON")) {
            try await make(body).refreshPlain()
        }
        await #expect(throws: UsageError.parseFailed("Failed to parse Command Code response as JSON")) {
            try await make(whoami: body).refreshPlain()
        }
    }

}
