import Testing
import Foundation
import Providers
@testable import DataSources
import Quotas
import Mockable
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Grok as data: the billing response read by `grok-billing.js` — the old
/// probe's fixtures, quota for quota.
@MainActor @Suite("Grok billing")
struct GrokDefinitionTests {

    private func parse(_ data: Data, providerId: String = "grok", accountEmail: String? = nil,
                       settings: String = "{}", settingsStatus: Int = 200) async throws -> UsageSnapshot {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let folder=root.appendingPathComponent(".grok")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var entry:[String:Any] = ["key":"fixture-token"]
        if let accountEmail { entry["email"]=accountEmail }
        try JSONSerialization.data(withJSONObject:["fixture-entry":entry]).write(to:folder.appendingPathComponent("auth.json"))
        let network=MockNetworkClient()
        given(network).request(.any).willProduce { @Sendable request in
            #expect(request.value(forHTTPHeaderField:"Authorization") == "Bearer fixture-token")
            if request.url?.absoluteString == "https://cli-chat-proxy.grok.com/v1/settings" {
                return (Data(settings.utf8),HTTPURLResponse(url:request.url!,statusCode:settingsStatus,httpVersion:nil,headerFields:nil)!)
            }
            #expect(request.url?.absoluteString == "https://cli-chat-proxy.grok.com/v1/billing?format=credits")
            return (data,HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!)
        }
        let provider=Provider(definition:try ProviderFactory.builtIn("grok"),settings:InMemoryProviderSettings(),makeDataSource:{source,_ in
            DataSources.make(source,providerId:"grok",cliExecutor:MockCLIExecutor(),network:network,makeTransport:{_,_,_,_ in MockRPCTransport()},scripts:ProviderFactory.builtInScripts,environment:{_ in nil},homeDirectory:root,now:{Date()})
        })
        return try await provider.refreshPlain()
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
    func `should show the weekly credits, each product and the prepaid balance, and no on-demand while its cap is zero`() async throws {
        let data = Data(Self.sampleResponse.utf8)

        let snapshot = try await parse(data, providerId: "grok")

        #expect(snapshot.providerId == "grok")
        // Weekly credits + 3 products + prepaid $2.49; on-demand skipped while its cap is 0
        #expect(snapshot.quotas.count == 5)
        #expect(snapshot.quotas.last?.left == .money(Money(Decimal(string: "2.49")!, currency: "USD"), of: nil))
    }

    @Test
    func `should show the weekly credits left`() async throws {
        let data = Data(Self.sampleResponse.utf8)

        let snapshot = try await parse(data, providerId: "grok")

        let weekly = try #require(snapshot.quota(for: .weekly))
        #expect(weekly.percentRemaining == 4.0) // 100 - 96
    }

    @Test
    func `should show what is left of Build, Imagine and Voice`() async throws {
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
    func `should reset the credits when the weekly billing period ends`() async throws {
        let data = Data(Self.sampleResponse.utf8)

        let snapshot = try await parse(data, providerId: "grok")

        let weekly = try #require(snapshot.quota(for: .weekly))
        let expectedEnd = try #require(OAuth2Refresher.parseDate("2026-07-30T05:09:24.881042+00:00"))
        #expect(weekly.resetsAt == expectedEnd)
        #expect(weekly.windowDuration == TimeInterval(7 * 24 * 3600))
    }

    @Test
    func `should show the login's email`() async throws {
        let data = Data(Self.sampleResponse.utf8)

        let snapshot = try await parse(data, providerId: "grok", accountEmail: "user@example.com")

        #expect(snapshot.accountEmail == "user@example.com")
    }

    @Test
    func `should show the credits as monthly when the billing period is monthly`() async throws {
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
    func `should show on-demand spend once it has a cap`() async throws {
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
    func `should show the credits as Usage, with no guessed window, when no period is stated`() async throws {
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
    func `should show no quotas when Grok reports nothing`() async throws {
        let snapshot = try await parse(Data("{}".utf8), providerId: "grok")

        #expect(snapshot.quotas.isEmpty)
    }

    @Test
    func `should show no quota, not a made-up 100%, when billing names a period but no usage`() async throws {
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
    func `should fail when Grok's billing answer isn't JSON`() async throws {
        await #expect(throws: UsageError.parseFailed("Failed to parse billing response as JSON")) {
            try await parse(Data("not json".utf8), providerId: "grok")
        }
    }

    // MARK: - Product Name Tests

    @Test
    func `should name Grok's products without the Grok prefix`() async throws {
        #expect(try await productName("GrokBuild") == "Build")
        #expect(try await productName("GrokImagine") == "Imagine")
        #expect(try await productName("GrokVoice") == "Voice")
    }

    @Test
    func `should name an unknown product in separate words`() async throws {
        #expect(try await productName("SomeNewProduct") == "Some New Product")
    }

    @Test
    func `should name a product called just Grok as Grok`() async throws {
        #expect(try await productName("Grok") == "Grok")
    }

    // MARK: - Plan, prepaid balance and billing period

    private func billing(_ config: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["config": config])
    }

    @Test
    func `should show the plan Grok's settings name`() async throws {
        let usage = try await parse(try billing(["creditUsagePercent": 10]), settings: #"{"subscription_tier_display":"SuperGrok Heavy"}"#)
        #expect(usage.accountTier == .custom("SuperGrok Heavy"))
    }

    @Test(arguments: [("SUPERGROK_HEAVY", "SuperGrok Heavy"), ("supergrok", "SuperGrok"), ("Grok Team", "Grok Team")])
    func `should name the plan from billing when Grok's settings don't`(_ tier: String, _ plan: String) async throws {
        let usage = try await parse(try billing(["creditUsagePercent": 10, "subscriptionTier": tier]))
        #expect(usage.accountTier == .custom(plan))
    }

    @Test
    func `should still show the credits when Grok's settings can't be read`() async throws {
        let usage = try await parse(try billing(["creditUsagePercent": 10]), settings: "oops", settingsStatus: 500)
        #expect(usage.quotas.first?.percentRemaining == 90)
        #expect(usage.accountTier == nil)
    }

    @Test
    func `should show the prepaid balance in dollars`() async throws {
        let usage = try await parse(try billing(["creditUsagePercent": 10, "prepaidBalance": ["val": "2490"]]))
        let prepaid = try #require(usage.quotas.first { $0.quotaType == .modelSpecific("Prepaid") })
        #expect(prepaid.left == .money(Money(Decimal(string: "24.9")!, currency: "USD"), of: nil))
    }

    @Test(arguments: [#"{}"#, #"{"val":0}"#])
    func `should leave out an empty prepaid balance rather than show it depleted`(_ balance: String) async throws {
        let usage = try await parse(Data(#"{"config":{"creditUsagePercent":10,"prepaidBalance":\#(balance)}}"#.utf8))
        #expect(!usage.quotas.contains { $0.quotaType == .modelSpecific("Prepaid") })
    }

    @Test
    func `should reset at the billing period's end when Grok names no current period`() async throws {
        let usage = try await parse(try billing(["creditUsagePercent": 10,
                                                 "billingPeriodStart": "2026-07-01T00:00:00+00:00",
                                                 "billingPeriodEnd": "2026-08-01T00:00:00+00:00"]))
        let credits = try #require(usage.quotas.first)
        #expect(credits.resetsAt == ISO8601DateFormatter().date(from: "2026-08-01T00:00:00Z"))
        #expect((credits.windowDuration ?? -1) == 31 * 86400)
    }
}
