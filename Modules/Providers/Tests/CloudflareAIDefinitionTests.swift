import DataSources
import Foundation
import Mockable
import Providers
import Quotas
import Testing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Cloudflare AI as data: the account the token sees, one GraphQL read of
/// Workers AI's neurons and tokens and AI Gateway's tokens and spend, the plan
/// from the subscriptions and the last invoice, read by `cloudflare-ai-usage.js`.
@MainActor @Suite
struct CloudflareAIDefinitionTests {
    /// 2026-10-05 14:30:00 UTC.
    private nonisolated static let now = Date(timeIntervalSince1970: 1_791_210_600)
    private static let api = "https://api.cloudflare.com/client/v4"

    static let accounts = #"{"success":true,"result":[{"id":"acc123","name":"Example"}]}"#
    static let paid = #"{"success":true,"result":[{"rate_plan":{"id":"r2_paid","public_name":"R2 Paid"}},{"rate_plan":{"id":"workers_paid","public_name":"Workers Paid"}}]}"#
    static let free = #"{"success":true,"result":[{"rate_plan":{"id":"teams_free","public_name":"Teams Free Base"}}]}"#
    static let refused = #"{"success":false,"errors":[{"code":10000,"message":"Authentication error"}],"result":null}"#
    static let bills = #"{"success":true,"result":[{"type":"invoice","occurred_at":"2026-09-21T03:00:00Z","amount_to_pay":14.2,"currency":"usd","status":"CLOSED"}]}"#

    /// GraphQL's answer: neurons so far today, Workers AI by day and model this month, AI Gateway by model.
    static func usage(today: Int? = 4200, days: String = Self.days, gateway: String = Self.gateway) -> String {
        let todayRows = today.map { #"[{"sum":{"totalNeurons":\#($0)}}]"# } ?? "[]"
        return #"{"data":{"viewer":{"accounts":[{"today":\#(todayRows),"days":\#(days),"gateway":\#(gateway)}]}},"errors":null}"#
    }

    /// Oct 1: 12k (2k over), Oct 2: 9k, Oct 3: 30k (20k over) — 22k neurons past the daily 10k.
    static let days = #"""
    [{"dimensions":{"date":"2026-10-01","modelId":"@cf/meta/llama-3.1-8b-instruct"},"sum":{"totalNeurons":7000,"totalInputTokens":800000,"totalOutputTokens":200000}},
     {"dimensions":{"date":"2026-10-01","modelId":"@cf/baai/bge-m3"},"sum":{"totalNeurons":5000,"totalInputTokens":300000,"totalOutputTokens":0}},
     {"dimensions":{"date":"2026-10-02","modelId":"@cf/meta/llama-3.1-8b-instruct"},"sum":{"totalNeurons":9000,"totalInputTokens":100000,"totalOutputTokens":40000}},
     {"dimensions":{"date":"2026-10-03","modelId":"@cf/meta/llama-3.1-8b-instruct"},"sum":{"totalNeurons":30000,"totalInputTokens":0,"totalOutputTokens":100000}}]
    """#

    static let gateway = #"""
    [{"dimensions":{"provider":"google-ai-studio","model":"gemini-3.5-flash"},"sum":{"cost":0.0059594999999999995,"tokensIn":1507,"tokensOut":411}},
     {"dimensions":{"provider":"openai","model":"gpt-5-mini"},"sum":{"cost":2.5,"tokensIn":900000,"tokensOut":120000}}]
    """#

    final class Seen: @unchecked Sendable {
        private let lock = NSLock()
        private var all: [URLRequest] = []
        func record(_ request: URLRequest) { lock.lock(); all.append(request); lock.unlock() }
        func request(to suffix: String) -> URLRequest? {
            lock.lock(); defer { lock.unlock() }
            return all.last { $0.url?.absoluteString.hasSuffix(suffix) == true }
        }
    }

    /// Answers each step by its URL: `(status, body)`.
    private func make(accounts: (Int, String) = (200, Self.accounts), usage: (Int, String) = (200, Self.usage()),
                      plan: (Int, String) = (200, Self.paid), bills: (Int, String) = (200, Self.bills),
                      environment: [String: String] = ["CLOUDFLARE_API_TOKEN": "cf-token"],
                      vault: MemoryVault = MemoryVault(), seen: Seen = Seen()) throws -> Provider {
        let definition = try ProviderFactory.builtIn("cloudflare-ai")
        let network = MockNetworkClient()
        given(network).request(.any).willProduce { @Sendable request in
            seen.record(request)
            let url = request.url?.absoluteString ?? ""
            let (status, body) = switch url {
            case "\(Self.api)/accounts": accounts
            case "\(Self.api)/graphql": usage
            case "\(Self.api)/accounts/acc123/subscriptions": plan
            case "\(Self.api)/accounts/acc123/billing/history?per_page=1": bills
            default: (404, "{}")
            }
            return (Data(body.utf8), StubbedProvider.response(status))
        }
        return Provider(definition: definition, settings: InMemoryProviderSettings(), makeDataSource: { source, login in
            DataSources.make(source, providerId: definition.id, cliExecutor: MockCLIExecutor(), network: network,
                             makeTransport: { _, _, _, _ in MockRPCTransport() }, scripts: ProviderFactory.builtInScripts,
                             secrets: vault.scoped(to: login), environment: { environment[$0] },
                             homeDirectory: FileManager.default.temporaryDirectory, now: { Self.now })
        }, vault: vault)
    }

    private func note(_ usage: UsageSnapshot, _ label: String) -> String? {
        usage.extensionMetrics?.first { $0.label == label }?.value
    }

    @Test
    func `should be Cloudflare AI, off until turned on, with its AI dashboard`() throws {
        let cloudflare = try make()
        #expect(cloudflare.id == "cloudflare-ai")
        #expect(cloudflare.name == "Cloudflare AI")
        #expect(cloudflare.plainIsInLineup == false)
        #expect(cloudflare.definition.profile.links.dashboard == URL(string: "https://dash.cloudflare.com/?to=/:account/ai/workers-ai"))
        #expect(cloudflare.definition.profile.links.status == URL(string: "https://www.cloudflarestatus.com"))
    }

    @Test
    func `should ask for the API token in Settings, and in Add Account for another account`() throws {
        let definition = try ProviderFactory.builtIn("cloudflare-ai")
        #expect(definition.defaultLoginSettings.map(\.id) == ["apiToken", "authEnvVar"])
        #expect(definition.accounts?.ways == [.form])
    }

    @Test
    func `should ask about the account the token sees, from today's and this month's start in UTC`() async throws {
        let seen = Seen()
        _ = try await make(seen: seen).refreshPlain()
        let graphql = try #require(seen.request(to: "/graphql"))
        #expect(graphql.httpMethod == "POST")
        #expect(graphql.value(forHTTPHeaderField: "Authorization") == "Bearer cf-token")
        let body = try #require(graphql.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        let variables = try #require(body["variables"] as? [String: String])
        #expect(variables == ["accountTag": "acc123", "day": "2026-10-05T00:00:00Z", "month": "2026-10-01"])
        #expect((body["query"] as? String)?.contains("aiInferenceAdaptiveGroups") == true)
        #expect((body["query"] as? String)?.contains("aiGatewayRequestsAdaptiveGroups") == true)
    }

    @Test
    func `should show today's neurons against the 10k a day, resetting at UTC midnight`() async throws {
        let usage = try await make().refreshPlain()
        let quota = try #require(usage.quotas.first)
        #expect(usage.quotas.count == 1)
        #expect(quota.quotaType == .modelSpecific("Workers AI neurons"))
        #expect(quota.percentRemaining == 58)
        #expect(quota.resetText == "4.2k / 10k neurons today")
        #expect(quota.resetsAt == Date(timeIntervalSince1970: 1_791_244_800))
        #expect(quota.windowDuration == 86_400)
        #expect(quota.group == "Workers AI")
    }

    @Test
    func `should show the whole day's neurons left when Workers AI ran nothing today`() async throws {
        let usage = try await make(usage: (200, Self.usage(today: nil, days: "[]", gateway: "[]"))).refreshPlain()
        #expect(usage.quotas.first?.percentRemaining == 100)
        #expect(usage.quotas.first?.resetText == "0 / 10k neurons today")
    }

    @Test
    func `should price each day's neurons past 10k on Workers Paid, never the month's total`() async throws {
        let usage = try await make().refreshPlain()
        let cost = try #require(usage.costUsage)
        #expect(usage.accountTier == .custom("Workers Paid"))
        #expect(cost.totalCost == Decimal(string: "0.242"))
        #expect(cost.resetText == "This month · est.")
        #expect(cost.lines == [CostLine(label: "Workers AI neurons", amount: Decimal(string: "0.242")!, detail: "22k past 10k a day")])
    }

    @Test
    func `should cost nothing on Free, which stops at the limit instead of charging`() async throws {
        let usage = try await make(plan: (200, Self.free)).refreshPlain()
        #expect(usage.accountTier == .custom("Free"))
        #expect(usage.costUsage == nil)
    }

    @Test(arguments: [403, 400])
    func `should leave the bill out and say why when the token can't read billing`(_ status: Int) async throws {
        let usage = try await make(plan: (status, Self.refused), bills: (status, Self.refused)).refreshPlain()
        #expect(usage.accountTier == nil)
        #expect(usage.costUsage == nil)
        #expect(note(usage, "Bill") == "Give the token Billing: Read to see the plan, the overage and invoices")
        #expect(usage.quotas.first?.percentRemaining == 58)
    }

    @Test
    func `should show this month's Workers AI tokens with the busiest models`() async throws {
        let usage = try await make().refreshPlain()
        #expect(note(usage, "Workers AI tokens") == "1.2M in · 340k out this month · llama-3.1-8b-instruct, bge-m3")
    }

    @Test
    func `should show AI Gateway's tokens and what the providers charge, apart from the Cloudflare bill`() async throws {
        let usage = try await make().refreshPlain()
        #expect(note(usage, "AI Gateway") == "1M tokens · $2.51 at providers (est.) this month · gpt-5-mini, gemini-3.5-flash")
        #expect(usage.extensionMetrics?.first { $0.label == "AI Gateway" }?.group == "AI Gateway")
        #expect(usage.costUsage?.totalCost == Decimal(string: "0.242"))
    }

    @Test
    func `should leave AI Gateway out when nothing went through it`() async throws {
        let usage = try await make(usage: (200, Self.usage(gateway: "[]"))).refreshPlain()
        #expect(note(usage, "AI Gateway") == nil)
    }

    @Test
    func `should show the last invoice`() async throws {
        let usage = try await make().refreshPlain()
        #expect(note(usage, "Last invoice") == "$14.20 · Sep 21")
    }

    @Test
    func `should use a pasted token when there is no environment token`() async throws {
        let seen = Seen()
        _ = try await make(environment: [:], vault: MemoryVault(["cloudflare-ai.apiToken": "pasted"]), seen: seen).refreshPlain()
        #expect(seen.request(to: "/graphql")?.value(forHTTPHeaderField: "Authorization") == "Bearer pasted")
    }

    @Test
    func `should ask for a token when there is none`() async throws {
        let cloudflare = try make(environment: [:])
        let account = cloudflare.defaultAccount
        await #expect(throws: UsageError.authenticationRequired) { try await cloudflare.refresh(account) }
        #expect(account.lastFailedStep == .lookup)
    }

    @Test(arguments: [400, 401, 403])
    func `should ask for a token that can read analytics when Cloudflare refuses it`(_ status: Int) async throws {
        let cloudflare = try make(accounts: (status, #"{"success":false,"errors":[{"code":9106,"message":"Authentication failed (status: 400)"}]}"#))
        await #expect(throws: UsageError.sessionExpired(hint: Self.tokenHint)) {
            try await cloudflare.refresh(cloudflare.defaultAccount)
        }
    }

    @Test
    func `should ask for analytics access when GraphQL won't show the account`() async throws {
        let denied = #"{"data":null,"errors":[{"message":"not authorized for that account","path":["viewer","accounts"],"extensions":{"code":"authz"}}]}"#
        let cloudflare = try make(usage: (200, denied))
        await #expect(throws: UsageError.sessionExpired(hint: Self.tokenHint)) {
            try await cloudflare.refresh(cloudflare.defaultAccount)
        }
    }

    @Test
    func `should say what GraphQL said when it can't answer`() async throws {
        let failed = #"{"data":null,"errors":[{"message":"query time range is too large","extensions":{"code":"bad_request"}}]}"#
        let cloudflare = try make(usage: (200, failed))
        let account = cloudflare.defaultAccount
        await #expect(throws: UsageError.parseFailed("Cloudflare: query time range is too large")) { try await cloudflare.refresh(account) }
        #expect(account.lastFailedStep == .mapping)
    }

    private static let tokenHint = "Use a Cloudflare API token with Account Analytics: Read."
}
