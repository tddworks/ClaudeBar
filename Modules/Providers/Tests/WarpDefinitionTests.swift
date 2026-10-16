import DataSources
import Foundation
import Mockable
import Providers
import Quotas
import Testing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Warp as data: the monthly credits and add-on credits from Warp's GraphQL
/// API with an API key, read by `warp-credits.js`.
@MainActor @Suite
struct WarpDefinitionTests {
    static let credits = #"""
    {"data":{"user":{"__typename":"UserOutput","user":{
     "requestLimitInfo":{"isUnlimited":false,"nextRefreshTime":"2026-02-28T19:16:33.462988Z","requestLimit":1500,"requestsUsedSinceLastRefresh":5},
     "bonusGrants":[{"requestCreditsGranted":20,"requestCreditsRemaining":10,"expiration":"2026-03-01T10:00:00Z"}],
     "workspaces":[{"bonusGrantsInfo":{"grants":[{"requestCreditsGranted":"15","requestCreditsRemaining":"5","expiration":"2026-03-15T10:00:00Z"}]}}]}}}}
    """#

    final class Seen: @unchecked Sendable {
        private let lock = NSLock()
        private var requests: [URLRequest] = []

        func record(_ request: URLRequest) {
            lock.lock(); defer { lock.unlock() }
            requests.append(request)
        }

        var last: URLRequest? {
            lock.lock(); defer { lock.unlock() }
            return requests.last
        }
    }

    private func make(body: String = Self.credits, status: Int = 200, environment: [String: String] = ["WARP_API_KEY": "wk-key"],
                      vault: MemoryVault = MemoryVault(), seen: Seen = Seen()) throws -> Provider {
        let definition = try ProviderFactory.builtIn("warp")
        let network = MockNetworkClient()
        given(network).request(.any).willProduce { @Sendable request in
            seen.record(request)
            guard request.url?.absoluteString == "https://app.warp.dev/graphql/v2?op=GetRequestLimitInfo",
                  request.httpMethod == "POST" else { return (Data(), StubbedProvider.response(400)) }
            return (Data(body.utf8), StubbedProvider.response(status))
        }
        return Provider(definition: definition, settings: InMemoryProviderSettings(), makeDataSource: { source, login in
            DataSources.make(source, providerId: definition.id, cliExecutor: MockCLIExecutor(), network: network,
                             makeTransport: { _, _, _, _ in MockRPCTransport() }, scripts: ProviderFactory.builtInScripts,
                             secrets: vault.scoped(to: login), environment: { environment[$0] },
                             homeDirectory: FileManager.default.temporaryDirectory, now: { Date() })
        }, vault: vault)
    }

    private func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    @Test
    func `should be Warp, off until turned on, with its dashboard and icon`() throws {
        let warp = try make()
        #expect(warp.id == "warp")
        #expect(warp.name == "Warp")
        #expect(warp.plainIsInLineup == false)
        #expect(warp.definition.profile.links.dashboard == URL(string: "https://app.warp.dev/settings/billing"))
        #expect(warp.definition.profile.look.icon == "WarpIcon")
    }

    @Test
    func `should ask Warp the way its app does, with the key, as JSON, and as Warp`() async throws {
        let seen = Seen()
        _ = try await make(seen: seen).refreshPlain()
        let request = try #require(seen.last)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer wk-key")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Warp/1.0")
        #expect(request.value(forHTTPHeaderField: "x-warp-client-id") == "warp-app")
        let body = try #require(request.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(body["operationName"] as? String == "GetRequestLimitInfo")
        #expect((body["query"] as? String)?.contains("requestLimitInfo") == true)
    }

    @Test
    func `should show the monthly credits used and when they refresh`() async throws {
        let usage = try await make().refreshPlain()
        let monthly = try #require(usage.quotas.first { $0.quotaType == .timeLimit("Monthly") })
        #expect(abs(monthly.percentRemaining - (1495.0 / 1500.0 * 100)) < 0.0001)
        #expect(monthly.resetText == "5/1500 credits")
        #expect(abs((monthly.resetsAt?.timeIntervalSince1970 ?? 0) - (date("2026-02-28T19:16:33.462988Z")?.timeIntervalSince1970 ?? -1)) < 0.001)
    }

    @Test
    func `should add up the add-on credits of the person and every workspace, with the soonest expiry`() async throws {
        let usage = try await make().refreshPlain()
        let addOn = try #require(usage.quotas.first { $0.quotaType == .modelSpecific("Add-on") })
        #expect(abs(addOn.percentRemaining - (15.0 / 35.0 * 100)) < 0.0001)
        #expect(addOn.resetText == "15/35 credits left")
        #expect(addOn.resetsAt == date("2026-03-01T10:00:00Z"))
    }

    @Test
    func `should show an unlimited plan as full, with no refresh countdown`() async throws {
        let body = #"{"data":{"user":{"__typename":"UserOutput","user":{"requestLimitInfo":{"isUnlimited":true,"nextRefreshTime":"2026-02-28T19:16:33Z","requestLimit":0,"requestsUsedSinceLastRefresh":40},"bonusGrants":[],"workspaces":[]}}}}"#
        let usage = try await make(body: body).refreshPlain()
        #expect(usage.quotas.count == 1)
        let monthly = try #require(usage.quotas.first)
        #expect(monthly.percentRemaining == 100)
        #expect(monthly.resetText == "Unlimited")
        #expect(monthly.resetsAt == nil)
    }

    @Test
    func `should read numbers Warp sends as text`() async throws {
        let body = #"{"data":{"user":{"__typename":"UserOutput","user":{"requestLimitInfo":{"isUnlimited":"false","nextRefreshTime":"2026-02-28T19:16:33Z","requestLimit":"100","requestsUsedSinceLastRefresh":"25"}}}}}"#
        let usage = try await make(body: body).refreshPlain()
        #expect(usage.quotas.first?.percentRemaining == 75)
    }

    @Test
    func `should use a pasted key when there is no environment key`() async throws {
        let seen = Seen()
        _ = try await make(environment: [:], vault: MemoryVault(["warp.apiKey": "wk-pasted"]), seen: seen).refreshPlain()
        #expect(seen.last?.value(forHTTPHeaderField: "Authorization") == "Bearer wk-pasted")
    }

    @Test
    func `should ask for a key when there is none`() async throws {
        let warp = try make(environment: [:])
        let account = warp.defaultAccount
        await #expect(throws: UsageError.authenticationRequired) { try await warp.refresh(account) }
        #expect(account.lastFailedStep == .lookup)
    }

    @Test
    func `should ask for a new key when Warp answers that the key is unauthorized`() async throws {
        let warp = try make(body: #"{"errors":[{"message":"Unauthorized"}]}"#)
        await #expect(throws: UsageError.sessionExpired(hint: "Create a new API key in Warp: Settings → Platform → API Keys.")) {
            try await warp.refresh(warp.defaultAccount)
        }
    }

    @Test
    func `should say what Warp answered when it reports another error`() async throws {
        let warp = try make(body: #"{"errors":[{"message":"Something broke"}]}"#)
        await #expect(throws: UsageError.executionFailed("Warp: Something broke")) { try await warp.refresh(warp.defaultAccount) }
    }

    @Test
    func `should fail reading the credits when Warp's answer has no limit`() async throws {
        let warp = try make(body: #"{"data":{"user":{"__typename":"UserOutput","user":{}}}}"#)
        let account = warp.defaultAccount
        await #expect(throws: UsageError.self) { try await warp.refresh(account) }
        #expect(account.lastFailedStep == .mapping)
    }
}
