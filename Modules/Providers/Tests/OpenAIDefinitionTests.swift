import DataSources
import Foundation
import Mockable
import Providers
import Quotas
import Testing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// OpenAI API as data: the organization's spend over the last 30 days from
/// the Admin API, asked from a start date the engine computes, read by
/// `openai-costs.js`.
@MainActor @Suite
struct OpenAIDefinitionTests {
    /// 2026-10-05 14:30:00 UTC; 29 days before its midnight is 2026-09-06.
    private nonisolated static let now = Date(timeIntervalSince1970: 1_791_210_600)
    private static let costsURL = "https://api.openai.com/v1/organization/costs?start_time=1788652800&bucket_width=1d&limit=30&group_by=line_item"

    static let costs = #"""
    {"object":"page","data":[
     {"object":"bucket","start_time":1788652800,"end_time":1788739200,"results":[
      {"object":"organization.costs.result","amount":{"value":12.5,"currency":"usd"},"line_item":"Text tokens"},
      {"object":"organization.costs.result","amount":{"value":"2.25","currency":"usd"},"line_item":"Web search tool calls"}]},
     {"object":"bucket","start_time":1788739200,"end_time":1788825600,"results":[
      {"object":"organization.costs.result","amount":{"value":0.1,"currency":"usd"},"line_item":"Text tokens"},
      {"object":"organization.costs.result","amount":{"value":null,"currency":"usd"},"line_item":null}]}],
     "has_more":false,"next_page":null}
    """#

    final class Seen: @unchecked Sendable {
        private let lock = NSLock()
        private var request: URLRequest?
        func record(_ request: URLRequest) { lock.lock(); self.request = request; lock.unlock() }
        var last: URLRequest? { lock.lock(); defer { lock.unlock() }; return request }
    }

    private func make(body: String = Self.costs, status: Int = 200, environment: [String: String] = ["OPENAI_ADMIN_KEY": "sk-admin"],
                      vault: MemoryVault = MemoryVault(), seen: Seen = Seen()) throws -> Provider {
        let definition = try ProviderFactory.builtIn("openai")
        let network = MockNetworkClient()
        given(network).request(.any).willProduce { @Sendable request in
            seen.record(request)
            return (Data(body.utf8), StubbedProvider.response(status))
        }
        return Provider(definition: definition, settings: InMemoryProviderSettings(), makeDataSource: { source, login in
            DataSources.make(source, providerId: definition.id, cliExecutor: MockCLIExecutor(), network: network,
                             makeTransport: { _, _, _, _ in MockRPCTransport() }, scripts: ProviderFactory.builtInScripts,
                             secrets: vault.scoped(to: login), environment: { environment[$0] },
                             homeDirectory: FileManager.default.temporaryDirectory, now: { Self.now })
        }, vault: vault)
    }

    @Test
    func `should be OpenAI API, off until turned on, with its usage page and status`() throws {
        let openai = try make()
        #expect(openai.id == "openai")
        #expect(openai.name == "OpenAI API")
        #expect(openai.plainIsInLineup == false)
        #expect(openai.definition.profile.links.dashboard == URL(string: "https://platform.openai.com/usage"))
        #expect(openai.definition.profile.links.status == URL(string: "https://status.openai.com"))
    }

    @Test
    func `should ask for the last 30 days of spend from today's UTC midnight, with the Admin key`() async throws {
        let seen = Seen()
        _ = try await make(seen: seen).refreshPlain()
        #expect(seen.last?.url?.absoluteString == Self.costsURL)
        #expect(seen.last?.value(forHTTPHeaderField: "Authorization") == "Bearer sk-admin")
    }

    @Test
    func `should add up the spend exactly, with a line per item, largest first`() async throws {
        let usage = try await make().refreshPlain()
        let cost = try #require(usage.costUsage)
        #expect(cost.totalCost == Decimal(string: "14.85"))
        #expect(cost.resetText == "Last 30 days")
        #expect(cost.lines.map(\.label) == ["Text tokens", "Web search tool calls"])
        #expect(cost.lines.map(\.amount) == [Decimal(string: "12.6"), Decimal(string: "2.25")])
        #expect(usage.quotas.isEmpty)
    }

    @Test
    func `should show nothing spent when the organization used nothing`() async throws {
        let usage = try await make(body: #"{"object":"page","data":[],"has_more":false,"next_page":null}"#).refreshPlain()
        #expect(usage.costUsage?.totalCost == 0)
        #expect(usage.costUsage?.lines.isEmpty == true)
    }

    @Test
    func `should use a pasted Admin key when there is no environment key`() async throws {
        let seen = Seen()
        _ = try await make(environment: [:], vault: MemoryVault(["openai.apiKey": "sk-pasted"]), seen: seen).refreshPlain()
        #expect(seen.last?.value(forHTTPHeaderField: "Authorization") == "Bearer sk-pasted")
    }

    @Test
    func `should ask for a key when there is none`() async throws {
        let openai = try make(environment: [:])
        let account = openai.defaultAccount
        await #expect(throws: UsageError.authenticationRequired) { try await openai.refresh(account) }
        #expect(account.lastFailedStep == .lookup)
    }

    @Test(arguments: [401, 403])
    func `should ask for an organization Admin key when OpenAI refuses the key`(_ status: Int) async throws {
        let openai = try make(status: status)
        await #expect(throws: UsageError.sessionExpired(hint: "Use an organization Admin API key; project keys can't read spend.")) {
            try await openai.refresh(openai.defaultAccount)
        }
    }

    @Test(arguments: ["not json", #"{"object":"page"}"#])
    func `should fail reading the spend when OpenAI's answer has no buckets`(_ body: String) async throws {
        let openai = try make(body: body)
        let account = openai.defaultAccount
        await #expect(throws: UsageError.self) { try await openai.refresh(account) }
        #expect(account.lastFailedStep == .mapping)
    }
}
