import Testing
import Foundation
import Providers
@testable import DataSources
import Quotas
import Mockable

/// Grok as data: the billing response read by `grok-billing.js` — the old
/// probe's fixtures, quota for quota.
@MainActor @Suite("Grok billing")
struct GrokDefinitionTests {

    private func parse(_ data: Data, providerId: String = "grok", accountEmail: String? = nil) async throws -> UsageSnapshot {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let folder=root.appendingPathComponent(".grok")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var entry:[String:Any] = ["key":"fixture-token"]
        if let accountEmail { entry["email"]=accountEmail }
        try JSONSerialization.data(withJSONObject:["fixture-entry":entry]).write(to:folder.appendingPathComponent("auth.json"))
        let network=MockNetworkClient()
        given(network).request(.any).willProduce { @Sendable request in
            #expect(request.url?.absoluteString == "https://cli-chat-proxy.grok.com/v1/billing?format=credits")
            #expect(request.value(forHTTPHeaderField:"Authorization") == "Bearer fixture-token")
            return (data,HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!)
        }
        let provider=Provider(definition:try Providers.builtIn("grok"),settings:InMemoryProviderSettings(),makeDataSource:{source,_ in
            DataSources.make(source,providerId:"grok",cliExecutor:MockCLIExecutor(),network:network,makeTransport:{_,_,_,_ in MockRPCTransport()},scripts:Providers.builtInScripts,environment:{_ in nil},homeDirectory:root,now:{Date()})
        })
        return try await provider.defaultAccount.refresh()
    }
    private func productName(_ name: String) async throws -> String {
        let data=try JSONSerialization.data(withJSONObject:["productUsage":[["product":name,"usagePercent":10]]])
        return try #require(try await parse(data).quotas.first).quotaType.displayName
    }


    /// Real response shape from `GET /v1/billing?format=credits`
    static let sampleResponse = """
    {
      "config": {
        "currentPeriod": {
          "type": "USAGE_PERIOD_TYPE_WEEKLY",
          "start": "2026-07-23T05:09:24.881042+00:00",
          "end": "2026-07-30T05:09:24.881042+00:00"
        },
        "creditUsagePercent": 96.0,
        "onDemandCap": {"val": 0},
        "onDemandUsed": {"val": 0},
        "productUsage": [
          {"product": "GrokBuild", "usagePercent": 84.0},
          {"product": "GrokImagine", "usagePercent": 11.0},
          {"product": "GrokVoice", "usagePercent": 1.0}
        ],
        "isUnifiedBillingUser": true,
        "prepaidBalance": {"val": 249},
        "topUpMethod": "TOP_UP_METHOD_SAVED_PAYMENT_METHOD",
        "billingPeriodStart": "2026-07-23T05:09:24.881042+00:00",
        "billingPeriodEnd": "2026-07-30T05:09:24.881042+00:00"
      }
    }
    """

    @Test
    func `parses overall credit usage and product quotas`() async throws {
        let data = Data(Self.sampleResponse.utf8)

        let snapshot = try await parse(data, providerId: "grok")

        #expect(snapshot.providerId == "grok")
        // Weekly credits + 3 products; on-demand skipped while its cap is 0
        #expect(snapshot.quotas.count == 4)
    }

    @Test
    func `maps credit usage percent to remaining`() async throws {
        let data = Data(Self.sampleResponse.utf8)

        let snapshot = try await parse(data, providerId: "grok")

        let weekly = try #require(snapshot.quota(for: .weekly))
        #expect(weekly.percentRemaining == 4.0) // 100 - 96
    }

    @Test
    func `maps product usage to model specific quotas`() async throws {
        let data = Data(Self.sampleResponse.utf8)

        let snapshot = try await parse(data, providerId: "grok")

        let build = try #require(snapshot.quota(for: .modelSpecific("Build")))
        #expect(build.percentRemaining == 16.0) // 100 - 84

        let imagine = try #require(snapshot.quota(for: .modelSpecific("Imagine")))
        #expect(imagine.percentRemaining == 89.0) // 100 - 11

        let voice = try #require(snapshot.quota(for: .modelSpecific("Voice")))
        #expect(voice.percentRemaining == 99.0) // 100 - 1
    }

    @Test
    func `parses period end as reset time with weekly window`() async throws {
        let data = Data(Self.sampleResponse.utf8)

        let snapshot = try await parse(data, providerId: "grok")

        let weekly = try #require(snapshot.quota(for: .weekly))
        let expectedEnd = try #require(OAuth2Refresher.parseDate("2026-07-30T05:09:24.881042+00:00"))
        #expect(weekly.resetsAt == expectedEnd)
        #expect(weekly.windowDuration == TimeInterval(7 * 24 * 3600))
    }

    @Test
    func `passes account email through`() async throws {
        let data = Data(Self.sampleResponse.utf8)

        let snapshot = try await parse(data, providerId: "grok", accountEmail: "user@example.com")

        #expect(snapshot.accountEmail == "user@example.com")
    }

    @Test
    func `monthly period maps to monthly time limit`() async throws {
        let json = """
        {
          "config": {
            "currentPeriod": {"type": "USAGE_PERIOD_TYPE_MONTHLY"},
            "creditUsagePercent": 50.0
          }
        }
        """

        let snapshot = try await parse(Data(json.utf8), providerId: "grok")

        let quota = try #require(snapshot.quotas.first)
        #expect(quota.quotaType == .timeLimit("Monthly"))
        #expect(quota.percentRemaining == 50.0)
    }

    @Test
    func `includes on demand quota once a cap is configured`() async throws {
        let json = """
        {
          "config": {
            "currentPeriod": {"type": "USAGE_PERIOD_TYPE_WEEKLY"},
            "creditUsagePercent": 10.0,
            "onDemandCap": {"val": 100},
            "onDemandUsed": {"val": 25}
          }
        }
        """

        let snapshot = try await parse(Data(json.utf8), providerId: "grok")

        let onDemand = try #require(snapshot.quota(for: .timeLimit("On-Demand")))
        #expect(onDemand.percentRemaining == 75.0)
    }

    @Test
    func `handles integer usage percentages`() async throws {
        let json = """
        {
          "config": {
            "creditUsagePercent": 96,
            "productUsage": [{"product": "GrokBuild", "usagePercent": 84}]
          }
        }
        """

        let snapshot = try await parse(Data(json.utf8), providerId: "grok")

        #expect(snapshot.quotas.count == 2)
        // No period stated: "Usage", never a guessed weekly window.
        #expect(snapshot.quota(for: .timeLimit("Usage"))?.percentRemaining == 4.0)
        #expect(snapshot.quota(for: .timeLimit("Usage"))?.window?.length == nil)
    }

    @Test
    func `handles empty response with no quotas`() async throws {
        let snapshot = try await parse(Data("{}".utf8), providerId: "grok")

        #expect(snapshot.quotas.isEmpty)
    }

    @Test
    func `shows full remaining when billing has a period but no usage percentages`() async throws {
        let json = """
        {
          "config": {
            "currentPeriod": {
              "type": "USAGE_PERIOD_TYPE_WEEKLY",
              "start": "2026-09-03T10:51:20.845630+00:00",
              "end": "2026-09-10T10:51:20.845630+00:00"
            },
            "onDemandCap": {"val": 0},
            "onDemandUsed": {"val": 0},
            "isUnifiedBillingUser": true,
            "prepaidBalance": {"val": 0}
          }
        }
        """

        let snapshot = try await parse(Data(json.utf8), providerId: "grok")

        // No usage reported is no quota — never a made-up 100% (the Left law).
        #expect(snapshot.quotas.isEmpty)
    }

    @Test
    func `throws parseFailed on invalid JSON`() async throws {
        await #expect(throws: UsageError.parseFailed("Failed to parse billing response as JSON")) {
            try await parse(Data("not json".utf8), providerId: "grok")
        }
    }

    // MARK: - Product Name Tests

    @Test
    func `strips Grok prefix from product names`() async throws {
        #expect(try await productName("GrokBuild") == "Build")
        #expect(try await productName("GrokImagine") == "Imagine")
        #expect(try await productName("GrokVoice") == "Voice")
    }

    @Test
    func `splits camel case for unknown products`() async throws {
        #expect(try await productName("SomeNewProduct") == "Some New Product")
    }

    @Test
    func `keeps bare Grok product name`() async throws {
        #expect(try await productName("Grok") == "Grok")
    }
}
