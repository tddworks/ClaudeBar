import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

@Suite("GrokUsageProbe Parsing Tests")
struct GrokUsageProbeParsingTests {

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
    func `parses overall credit usage and product quotas`() throws {
        let data = Data(Self.sampleResponse.utf8)

        let snapshot = try GrokUsageProbe.parseResponse(data, providerId: "grok")

        #expect(snapshot.providerId == "grok")
        // Weekly credits + 3 products; on-demand skipped while its cap is 0
        #expect(snapshot.quotas.count == 4)
    }

    @Test
    func `maps credit usage percent to remaining`() throws {
        let data = Data(Self.sampleResponse.utf8)

        let snapshot = try GrokUsageProbe.parseResponse(data, providerId: "grok")

        let weekly = try #require(snapshot.quota(for: .weekly))
        #expect(weekly.percentRemaining == 4.0) // 100 - 96
    }

    @Test
    func `maps product usage to model specific quotas`() throws {
        let data = Data(Self.sampleResponse.utf8)

        let snapshot = try GrokUsageProbe.parseResponse(data, providerId: "grok")

        let build = try #require(snapshot.quota(for: .modelSpecific("Build")))
        #expect(build.percentRemaining == 16.0) // 100 - 84

        let imagine = try #require(snapshot.quota(for: .modelSpecific("Imagine")))
        #expect(imagine.percentRemaining == 89.0) // 100 - 11

        let voice = try #require(snapshot.quota(for: .modelSpecific("Voice")))
        #expect(voice.percentRemaining == 99.0) // 100 - 1
    }

    @Test
    func `parses period end as reset time with weekly window`() throws {
        let data = Data(Self.sampleResponse.utf8)

        let snapshot = try GrokUsageProbe.parseResponse(data, providerId: "grok")

        let weekly = try #require(snapshot.quota(for: .weekly))
        let expectedEnd = try #require(GrokCredentialLoader.parseDate("2026-07-30T05:09:24.881042+00:00"))
        #expect(weekly.resetsAt == expectedEnd)
        #expect(weekly.windowDuration == TimeInterval(7 * 24 * 3600))
    }

    @Test
    func `passes account email through`() throws {
        let data = Data(Self.sampleResponse.utf8)

        let snapshot = try GrokUsageProbe.parseResponse(data, providerId: "grok", accountEmail: "user@example.com")

        #expect(snapshot.accountEmail == "user@example.com")
    }

    @Test
    func `monthly period maps to monthly time limit`() throws {
        let json = """
        {
          "config": {
            "currentPeriod": {"type": "USAGE_PERIOD_TYPE_MONTHLY"},
            "creditUsagePercent": 50.0
          }
        }
        """

        let snapshot = try GrokUsageProbe.parseResponse(Data(json.utf8), providerId: "grok")

        let quota = try #require(snapshot.quotas.first)
        #expect(quota.quotaType == .timeLimit("Monthly"))
        #expect(quota.percentRemaining == 50.0)
    }

    @Test
    func `includes on demand quota once a cap is configured`() throws {
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

        let snapshot = try GrokUsageProbe.parseResponse(Data(json.utf8), providerId: "grok")

        let onDemand = try #require(snapshot.quota(for: .timeLimit("On-Demand")))
        #expect(onDemand.percentRemaining == 75.0)
    }

    @Test
    func `handles integer usage percentages`() throws {
        let json = """
        {
          "config": {
            "creditUsagePercent": 96,
            "productUsage": [{"product": "GrokBuild", "usagePercent": 84}]
          }
        }
        """

        let snapshot = try GrokUsageProbe.parseResponse(Data(json.utf8), providerId: "grok")

        #expect(snapshot.quotas.count == 2)
        #expect(snapshot.quota(for: .weekly)?.percentRemaining == 4.0)
    }

    @Test
    func `handles empty response with no quotas`() throws {
        let snapshot = try GrokUsageProbe.parseResponse(Data("{}".utf8), providerId: "grok")

        #expect(snapshot.quotas.isEmpty)
    }

    @Test
    func `shows full remaining when billing has a period but no usage percentages`() throws {
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

        let snapshot = try GrokUsageProbe.parseResponse(Data(json.utf8), providerId: "grok")

        let weekly = try #require(snapshot.quota(for: .weekly))
        #expect(weekly.percentRemaining == 100)
        let expectedEnd = try #require(GrokCredentialLoader.parseDate("2026-09-10T10:51:20.845630+00:00"))
        #expect(weekly.resetsAt == expectedEnd)
        #expect(weekly.windowDuration == 604_800)
    }

    @Test
    func `throws parseFailed on invalid JSON`() {
        #expect(throws: ProbeError.parseFailed("Failed to parse billing response as JSON")) {
            try GrokUsageProbe.parseResponse(Data("not json".utf8), providerId: "grok")
        }
    }

    // MARK: - Product Name Tests

    @Test
    func `strips Grok prefix from product names`() {
        #expect(GrokUsageProbe.productDisplayName("GrokBuild") == "Build")
        #expect(GrokUsageProbe.productDisplayName("GrokImagine") == "Imagine")
        #expect(GrokUsageProbe.productDisplayName("GrokVoice") == "Voice")
    }

    @Test
    func `splits camel case for unknown products`() {
        #expect(GrokUsageProbe.productDisplayName("SomeNewProduct") == "Some New Product")
    }

    @Test
    func `keeps bare Grok product name`() {
        #expect(GrokUsageProbe.productDisplayName("Grok") == "Grok")
    }
}
