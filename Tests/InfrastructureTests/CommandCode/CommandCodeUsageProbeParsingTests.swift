import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

@Suite("CommandCodeUsageProbe Parsing Tests")
struct CommandCodeUsageProbeParsingTests {

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

    private func parse(_ json: String, accountEmail: String? = nil) throws -> UsageSnapshot {
        try CommandCodeUsageProbe.parseResponse(
            Data(json.utf8),
            providerId: "commandcode",
            accountEmail: accountEmail
        )
    }

    @Test
    func `parses provider id`() throws {
        #expect(try parse(Self.sampleResponse).providerId == "commandcode")
    }

    @Test
    func `maps five hour window to session quota`() throws {
        let session = try #require(try parse(Self.sampleResponse).quota(for: .session))

        #expect(session.percentRemaining == 75)
        #expect(session.resetsAt == Date(timeIntervalSince1970: 1_770_000_000))
        #expect(session.windowDuration == TimeInterval(5 * 3600))
    }

    @Test
    func `maps weekly window to weekly quota`() throws {
        let weekly = try #require(try parse(Self.sampleResponse).quota(for: .weekly))

        #expect(weekly.percentRemaining == 75)
        #expect(weekly.resetsAt == Date(timeIntervalSince1970: 1_770_500_000))
        #expect(weekly.windowDuration == TimeInterval(7 * 24 * 3600))
    }

    @Test
    func `maps plan allowance to a credits meter`() throws {
        let credits = try #require(try parse(Self.sampleResponse).quota(for: .timeLimit("Credits")))

        #expect(credits.percentRemaining == 85) // 8.5 of 10
        #expect(credits.dollarRemaining == 8.5)
        #expect(credits.dollarUsed == 1.5)
        #expect(credits.dollarCap == 10)
    }

    @Test
    func `passes account email through`() throws {
        let snapshot = try parse(Self.sampleResponse, accountEmail: "alice@example.com")

        #expect(snapshot.accountEmail == "alice@example.com")
    }

    @Test
    func `unwraps a data envelope`() throws {
        let json = """
        { "data": \(Self.sampleResponse) }
        """

        let snapshot = try parse(json)

        #expect(snapshot.quota(for: .session)?.percentRemaining == 75)
        #expect(snapshot.quota(for: .timeLimit("Credits"))?.dollarRemaining == 8.5)
    }

    @Test
    func `returns empty snapshot for empty object`() throws {
        #expect(try parse("{}").quotas.isEmpty)
    }

    @Test
    func `throws parseFailed on invalid JSON`() {
        #expect(throws: ProbeError.parseFailed("Failed to parse Command Code response as JSON")) {
            try CommandCodeUsageProbe.parseResponse(Data("not json".utf8), providerId: "commandcode")
        }
    }

    @Test
    func `skips a window with zero cap`() throws {
        let json = """
        {
          "windowLimits": {
            "fiveHour": { "used": 0, "cap": 0, "resetAt": 1770000000000 },
            "weekly": { "used": 50, "cap": 200, "resetAt": 1770500000000 }
          }
        }
        """

        let snapshot = try parse(json)

        #expect(snapshot.quota(for: .session) == nil)
        #expect(snapshot.quota(for: .weekly)?.percentRemaining == 75)
    }

    @Test
    func `treats missing used as zero`() throws {
        let json = """
        { "windowLimits": { "fiveHour": { "cap": 40, "resetAt": 1770000000000 } } }
        """

        #expect(try parse(json).quota(for: .session)?.percentRemaining == 100)
    }

    @Test
    func `parses ISO-8601 reset timestamp`() throws {
        let json = """
        { "windowLimits": { "fiveHour": { "used": 10, "cap": 40, "resetAt": "2026-09-11T12:00:00Z" } } }
        """

        let session = try #require(try parse(json).quota(for: .session))

        #expect(session.resetsAt == Date(timeIntervalSince1970: 1_789_128_000))
    }

    @Test
    func `parses epoch-second reset timestamp`() throws {
        let json = """
        { "windowLimits": { "fiveHour": { "used": 10, "cap": 40, "resetAt": 1770000000 } } }
        """

        let session = try #require(try parse(json).quota(for: .session))

        #expect(session.resetsAt == Date(timeIntervalSince1970: 1_770_000_000))
    }

    @Test
    func `prefers the longest matching plan id`() throws {
        // individual-pro-v1 ($80) must not match individual-pro ($30)
        let json = """
        { "credits": { "monthlyCredits": 80, "purchasedCredits": 0, "freeCredits": 0, "planId": "individual-pro-v1" } }
        """

        let credits = try #require(try parse(json).quota(for: .timeLimit("Credits")))

        #expect(credits.percentRemaining == 100)
        #expect(credits.dollarCap == 80)
    }

    @Test
    func `normalizes underscores and case in plan id`() throws {
        let json = """
        { "credits": { "monthlyCredits": 4, "purchasedCredits": 0, "freeCredits": 0, "planId": "Teams_Pro" } }
        """

        let credits = try #require(try parse(json).quota(for: .timeLimit("Credits")))

        #expect(credits.percentRemaining == 10) // 4 of 40
        #expect(credits.dollarCap == 40)
    }

    @Test
    func `adds purchased and free credits to the allowance`() throws {
        let json = """
        {
          "credits": {
            "monthlyCredits": 2, "purchasedCredits": 20, "freeCredits": 3, "planId": "individual-go"
          }
        }
        """

        let credits = try #require(try parse(json).quota(for: .timeLimit("Credits")))

        #expect(credits.dollarRemaining == 25)
        #expect(credits.dollarCap == 33) // plan 10 + purchased 20 + free 3
    }

    @Test
    func `shows a balance-only meter for an unknown plan with no windows`() throws {
        let json = """
        { "credits": { "monthlyCredits": 12.5, "purchasedCredits": 0, "freeCredits": 0, "planId": "mystery-tier" } }
        """

        let credits = try #require(try parse(json).quota(for: .timeLimit("Credits")))

        #expect(credits.percentRemaining == 100)
        #expect(credits.dollarRemaining == 12.5)
        #expect(credits.dollarCap == nil)
    }

    @Test
    func `skips a balance-only meter when windows already report usage`() throws {
        let json = """
        {
          "credits": { "monthlyCredits": 12.5, "planId": "mystery-tier" },
          "windowLimits": { "weekly": { "used": 50, "cap": 200, "resetAt": 1770500000000 } }
        }
        """

        let snapshot = try parse(json)

        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quota(for: .weekly) != nil)
    }

    @Test
    func `reports zero remaining when the plan allowance is exhausted`() throws {
        let json = """
        { "credits": { "monthlyCredits": 0, "purchasedCredits": 0, "freeCredits": 0, "planId": "individual-go" } }
        """

        let snapshot = try parse(json)

        #expect(snapshot.quota(for: .timeLimit("Credits"))?.percentRemaining == 0)
    }

    @Test
    func `reports over-cap windows as negative remaining`() throws {
        let json = """
        { "windowLimits": { "fiveHour": { "used": 44, "cap": 40, "resetAt": 1770000000000 } } }
        """

        #expect(try parse(json).quota(for: .session)?.percentRemaining == -10)
    }
}
