import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

@Suite
struct AntigravityQuotaSummaryParserTests {

    static let remoteSummary = """
    {
      "groups": [
        {
          "displayName": "Gemini",
          "buckets": [
            { "bucketId": "gemini-5h", "remainingFraction": 0.8, "resetTime": "2025-01-01T05:00:00Z" },
            { "bucketId": "gemini-weekly", "remainingFraction": 0.6, "resetTime": "2025-01-07T00:00:00Z" }
          ]
        },
        {
          "displayName": "Claude & others",
          "buckets": [
            { "bucketId": "3p-5h", "remainingFraction": 0.4 },
            { "bucketId": "3p-weekly", "remainingFraction": 0.2 },
            { "bucketId": "gemini-image-5h", "remainingFraction": 1.0 }
          ]
        }
      ]
    }
    """

    static var languageServerSummary: String {
        #"{"response": \#(remoteSummary)}"#
    }

    @Test
    func `maps the four known buckets to quotas in fixed order`() throws {
        let quotas = try #require(AntigravityQuotaSummaryParser.parse(Data(Self.remoteSummary.utf8), providerId: "antigravity"))

        #expect(quotas.count == 4)
        #expect(quotas[0].quotaType == .session)
        #expect(quotas[0].percentRemaining == 80.0)
        #expect(quotas[0].resetsAt == ISO8601DateFormatter().date(from: "2025-01-01T05:00:00Z"))
        #expect(quotas[1].quotaType == .weekly)
        #expect(quotas[1].percentRemaining == 60.0)
        #expect(quotas[2].quotaType == .modelSpecific("Claude"))
        #expect(quotas[2].percentRemaining == 40.0)
        #expect(quotas[3].quotaType == .modelSpecific("Claude Weekly"))
        #expect(quotas[3].percentRemaining == 20.0)
        #expect(quotas.allSatisfy { $0.providerId == "antigravity" })
    }

    @Test
    func `assigns consistent menu bar titles so Gemini mirrors Claude format`() throws {
        let quotas = try #require(AntigravityQuotaSummaryParser.parse(Data(Self.remoteSummary.utf8), providerId: "antigravity"))

        // Gemini pool: should show "Gemini" / "Gemini Weekly" — not the generic "5h" / "7d"
        #expect(quotas[0].menuBarTitle == "Gemini",        "gemini-5h should use 'Gemini' as menu bar prefix")
        #expect(quotas[1].menuBarTitle == "Gemini Weekly", "gemini-weekly should use 'Gemini Weekly' as menu bar prefix")

        // Claude pool: already correct, verified here for symmetry
        #expect(quotas[2].menuBarTitle == "Claude",        "3p-5h should use 'Claude' as menu bar prefix")
        #expect(quotas[3].menuBarTitle == "Claude Weekly", "3p-weekly should use 'Claude Weekly' as menu bar prefix")
    }

    @Test
    func `accepts the language server response envelope`() throws {
        let quotas = try #require(AntigravityQuotaSummaryParser.parse(Data(Self.languageServerSummary.utf8), providerId: "antigravity"))

        #expect(quotas.count == 4)
    }

    @Test
    func `ignores unknown buckets`() throws {
        let quotas = try #require(AntigravityQuotaSummaryParser.parse(Data(Self.remoteSummary.utf8), providerId: "antigravity"))

        #expect(!quotas.contains { $0.quotaType == .modelSpecific("gemini-image-5h") })
    }

    @Test
    func `drops a bucket without remainingFraction instead of fabricating a value`() throws {
        let json = """
        {"groups":[{"buckets":[{"bucketId":"gemini-5h"},{"bucketId":"gemini-weekly","remainingFraction":0.5}]}]}
        """

        let quotas = try #require(AntigravityQuotaSummaryParser.parse(Data(json.utf8), providerId: "antigravity"))

        #expect(quotas.count == 1)
        #expect(quotas[0].quotaType == .weekly)
    }

    @Test
    func `returns nil when the payload is not a quota summary`() {
        #expect(AntigravityQuotaSummaryParser.parse(Data("not json".utf8), providerId: "antigravity") == nil)
        #expect(AntigravityQuotaSummaryParser.parse(Data(#"{"userStatus":{}}"#.utf8), providerId: "antigravity") == nil)
    }

    @Test
    func `returns empty array when summary has no known buckets`() {
        let quotas = AntigravityQuotaSummaryParser.parse(Data(#"{"groups":[]}"#.utf8), providerId: "antigravity")

        #expect(quotas?.isEmpty == true)
    }
}
