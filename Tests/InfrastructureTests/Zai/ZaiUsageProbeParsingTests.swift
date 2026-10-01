import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

@Suite
struct ZaiUsageProbeParsingTests {

    // MARK: - Sample Data

    static let sampleQuotaLimitResponse = """
    {
      "data": {
        "limits": [
          {
            "type": "TOKENS_LIMIT",
            "percentage": 65
          },
          {
            "type": "TIME_LIMIT",
            "percentage": 30,
            "currentValue": 100,
            "usage": 3600,
            "usageDetails": []
          }
        ]
      }
    }
    """

    static let sampleQuotaLimitResponseOnlyTokens = """
    {
      "data": {
        "limits": [
          {
            "type": "TOKENS_LIMIT",
            "percentage": 45
          }
        ]
      }
    }
    """

    static let sampleQuotaLimitResponseEmpty = """
    {
      "data": {
        "limits": []
      }
    }
    """

    static let sampleQuotaLimitResponseFullUsage = """
    {
      "data": {
        "limits": [
          {
            "type": "TOKENS_LIMIT",
            "percentage": 100
          }
        ]
      }
    }
    """

    static let sampleQuotaLimitResponseNoUsage = """
    {
      "data": {
        "limits": [
          {
            "type": "TOKENS_LIMIT",
            "percentage": 0
          }
        ]
      }
    }
    """

    // MARK: - Quota Limit Parsing Tests

    @Test
    func `parses quota limits into UsageQuota`() throws {
        // Given
        let data = Data(Self.sampleQuotaLimitResponse.utf8)

        // When
        let snapshot = try ZaiUsageProbe.parseQuotaLimitResponse(data, providerId: "zai")

        // Then
        #expect(snapshot.quotas.count == 2)
    }

    @Test
    func `maps percentage used to percentRemaining`() throws {
        // Given
        let data = Data(Self.sampleQuotaLimitResponse.utf8)

        // When
        let snapshot = try ZaiUsageProbe.parseQuotaLimitResponse(data, providerId: "zai")

        // Then - percentage is "used", so remaining = 100 - used
        let tokenQuota = snapshot.quotas.first { $0.quotaType == .session }
        #expect(tokenQuota != nil)
        #expect(tokenQuota?.percentRemaining == 35.0) // 100 - 65 = 35
    }

    @Test
    func `creates session quota type for TOKENS_LIMIT`() throws {
        // Given
        let data = Data(Self.sampleQuotaLimitResponse.utf8)

        // When
        let snapshot = try ZaiUsageProbe.parseQuotaLimitResponse(data, providerId: "zai")

        // Then
        let tokenQuota = snapshot.quotas.first { $0.quotaType == .session }
        #expect(tokenQuota != nil)
    }

    @Test
    func `creates MCP quota type for TIME_LIMIT`() throws {
        // Given
        let data = Data(Self.sampleQuotaLimitResponse.utf8)

        // When
        let snapshot = try ZaiUsageProbe.parseQuotaLimitResponse(data, providerId: "zai")

        // Then
        let timeQuota = snapshot.quotas.first { $0.quotaType == .timeLimit("MCP") }
        #expect(timeQuota != nil)
        #expect(timeQuota?.percentRemaining == 70.0) // 100 - 30 = 70
    }

    @Test
    func `handles only TOKENS_LIMIT present`() throws {
        // Given
        let data = Data(Self.sampleQuotaLimitResponseOnlyTokens.utf8)

        // When
        let snapshot = try ZaiUsageProbe.parseQuotaLimitResponse(data, providerId: "zai")

        // Then
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas.first?.quotaType == .session)
        #expect(snapshot.quotas.first?.percentRemaining == 55.0) // 100 - 45 = 55
    }

    @Test
    func `sets providerId correctly`() throws {
        // Given
        let data = Data(Self.sampleQuotaLimitResponse.utf8)

        // When
        let snapshot = try ZaiUsageProbe.parseQuotaLimitResponse(data, providerId: "zai")

        // Then
        #expect(snapshot.providerId == "zai")
        #expect(snapshot.quotas.allSatisfy { $0.providerId == "zai" })
    }

    @Test
    func `treats 100% used as 0% remaining`() throws {
        // Given
        let data = Data(Self.sampleQuotaLimitResponseFullUsage.utf8)

        // When
        let snapshot = try ZaiUsageProbe.parseQuotaLimitResponse(data, providerId: "zai")

        // Then
        #expect(snapshot.quotas.first?.percentRemaining == 0.0)
    }

    @Test
    func `treats 0% used as 100% remaining`() throws {
        // Given
        let data = Data(Self.sampleQuotaLimitResponseNoUsage.utf8)

        // When
        let snapshot = try ZaiUsageProbe.parseQuotaLimitResponse(data, providerId: "zai")

        // Then
        #expect(snapshot.quotas.first?.percentRemaining == 100.0)
    }

    // MARK: - Error Handling Tests

    @Test
    func `throws parseFailed for invalid JSON`() throws {
        // Given
        let invalidData = Data("not json".utf8)

        // When/Then
        #expect(throws: ProbeError.self) {
            try ZaiUsageProbe.parseQuotaLimitResponse(invalidData, providerId: "zai")
        }
    }

    @Test
    func `throws parseFailed when no limits found`() throws {
        // Given
        let data = Data(Self.sampleQuotaLimitResponseEmpty.utf8)

        // When/Then
        #expect(throws: ProbeError.self) {
            try ZaiUsageProbe.parseQuotaLimitResponse(data, providerId: "zai")
        }
    }

    @Test
    func `handles missing data field gracefully`() throws {
        // Given
        let responseWithoutData = """
        {
          "error": "Unauthorized"
        }
        """
        let data = Data(responseWithoutData.utf8)

        // When/Then
        #expect(throws: ProbeError.self) {
            try ZaiUsageProbe.parseQuotaLimitResponse(data, providerId: "zai")
        }
    }

    // MARK: - TOKENS_LIMIT unit-distinguishing Tests
    //
    // Z.ai's GLM Coding Plan API returns multiple TOKENS_LIMIT entries
    // distinguished only by the `unit` field. Without parsing `unit`,
    // both entries collapse into the same QuotaType and one (typically the
    // weekly cap — the most user-visible one) gets silently dropped.
    //
    // Observed unit mapping (May 2026):
    //   TIME_LIMIT  unit=5  -> MCP / tools usage
    //   TOKENS_LIMIT unit=3 -> rolling 5-hour session quota
    //   TOKENS_LIMIT unit=6 -> rolling 7-day weekly quota
    //   TOKENS_LIMIT unit=7 -> monthly quota (plan-tier dependent)

    static let sampleQuotaLimitResponseRealZai = """
    {
      "data": {
        "limits": [
          { "type": "TIME_LIMIT", "unit": 5, "percentage": 1, "nextResetTime": 1778591596997 },
          { "type": "TOKENS_LIMIT", "unit": 3, "percentage": 13, "nextResetTime": 1778100911330 },
          { "type": "TOKENS_LIMIT", "unit": 6, "percentage": 46, "nextResetTime": 1778418796990 }
        ]
      }
    }
    """

    @Test
    func `parses real z.ai response with all three quota tiers (session/weekly/MCP)`() throws {
        let data = Data(Self.sampleQuotaLimitResponseRealZai.utf8)
        let snapshot = try ZaiUsageProbe.parseQuotaLimitResponse(data, providerId: "zai")

        #expect(snapshot.quotas.count == 3)
        #expect(snapshot.quotas.contains { $0.quotaType == .session })
        #expect(snapshot.quotas.contains { $0.quotaType == .weekly })
        #expect(snapshot.quotas.contains { $0.quotaType == .timeLimit("MCP") })
    }

    @Test
    func `maps TOKENS_LIMIT unit=3 to session`() throws {
        let json = """
        { "data": { "limits": [
          { "type": "TOKENS_LIMIT", "unit": 3, "percentage": 13 }
        ] } }
        """
        let snapshot = try ZaiUsageProbe.parseQuotaLimitResponse(Data(json.utf8), providerId: "zai")
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas.first?.quotaType == .session)
        #expect(snapshot.quotas.first?.percentRemaining == 87.0)
    }

    @Test
    func `maps TOKENS_LIMIT unit=6 to weekly`() throws {
        let json = """
        { "data": { "limits": [
          { "type": "TOKENS_LIMIT", "unit": 6, "percentage": 46 }
        ] } }
        """
        let snapshot = try ZaiUsageProbe.parseQuotaLimitResponse(Data(json.utf8), providerId: "zai")
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas.first?.quotaType == .weekly)
        #expect(snapshot.quotas.first?.percentRemaining == 54.0)
    }

    @Test
    func `does not collapse session and weekly into same quota`() throws {
        // Regression test: prior implementation mapped both TOKENS_LIMIT entries
        // to .session, so the second one (weekly) was effectively hidden.
        let data = Data(Self.sampleQuotaLimitResponseRealZai.utf8)
        let snapshot = try ZaiUsageProbe.parseQuotaLimitResponse(data, providerId: "zai")

        let sessionQuotas = snapshot.quotas.filter { $0.quotaType == .session }
        let weeklyQuotas = snapshot.quotas.filter { $0.quotaType == .weekly }
        #expect(sessionQuotas.count == 1)
        #expect(weeklyQuotas.count == 1)
        #expect(sessionQuotas.first?.percentRemaining != weeklyQuotas.first?.percentRemaining)
    }

    @Test
    func `legacy TOKENS_LIMIT response without unit still maps to session (backward-compat)`() throws {
        // Existing tests use payloads without `unit` — preserve original behavior.
        let json = """
        { "data": { "limits": [
          { "type": "TOKENS_LIMIT", "percentage": 65 }
        ] } }
        """
        let snapshot = try ZaiUsageProbe.parseQuotaLimitResponse(Data(json.utf8), providerId: "zai")
        #expect(snapshot.quotas.first?.quotaType == .session)
    }

    @Test
    func `unknown TOKENS_LIMIT unit is preserved via modelSpecific (no silent drop)`() throws {
        let json = """
        { "data": { "limits": [
          { "type": "TOKENS_LIMIT", "unit": 99, "percentage": 25 }
        ] } }
        """
        let snapshot = try ZaiUsageProbe.parseQuotaLimitResponse(Data(json.utf8), providerId: "zai")
        #expect(snapshot.quotas.count == 1)
        if case .modelSpecific(let label) = snapshot.quotas.first?.quotaType {
            #expect(label.contains("99"))
        } else {
            Issue.record("Expected .modelSpecific quota type for unknown unit, got \(String(describing: snapshot.quotas.first?.quotaType))")
        }
    }

    @Test
    func `clamps percentage to valid range`() throws {
        // Given - edge case where percentage might be negative or > 100
        let responseWithInvalidPercentage = """
        {
          "data": {
            "limits": [
              {
                "type": "TOKENS_LIMIT",
                "percentage": -10
              },
              {
                "type": "TIME_LIMIT",
                "percentage": 150
              }
            ]
          }
        }
        """
        let data = Data(responseWithInvalidPercentage.utf8)

        // When
        let snapshot = try ZaiUsageProbe.parseQuotaLimitResponse(data, providerId: "zai")

        // Then - should clamp to 0-100 range
        #expect(snapshot.quotas.count == 2)
        #expect(snapshot.quotas[0].percentRemaining >= 0 && snapshot.quotas[0].percentRemaining <= 100)
        #expect(snapshot.quotas[1].percentRemaining >= 0 && snapshot.quotas[1].percentRemaining <= 100)
    }

    // MARK: - CREDIT_LIMIT Tests
    //
    // Credit-based plan tiers (e.g. GLM Coding Lite) report quota entries with
    // type CREDIT_LIMIT instead of TOKENS_LIMIT, using the same `unit` semantics.
    // Because the switch only matched TOKENS_LIMIT/TIME_LIMIT tuples, every entry
    // fell through to `continue` and the probe failed outright with
    // "No recognized quota types found".

    static let sampleQuotaLimitResponseCreditPlan = """
    {
      "data": {
        "limits": [
          { "type": "CREDIT_LIMIT", "unit": 3, "number": 5, "usage": 2000,
            "currentValue": 0, "remaining": 2000, "percentage": 0 },
          { "type": "CREDIT_LIMIT", "unit": 6, "number": 1, "usage": 10000,
            "currentValue": 2004, "remaining": 7995, "percentage": 20,
            "nextResetTime": 1786112351998 }
        ],
        "level": "lite"
      }
    }
    """

    @Test
    func `parses credit-based plan response instead of failing`() throws {
        let data = Data(Self.sampleQuotaLimitResponseCreditPlan.utf8)
        let snapshot = try ZaiUsageProbe.parseQuotaLimitResponse(data, providerId: "zai")

        #expect(snapshot.quotas.count == 2)
        #expect(snapshot.quotas.contains { $0.quotaType == .session })
        #expect(snapshot.quotas.contains { $0.quotaType == .weekly })
    }

    @Test
    func `maps CREDIT_LIMIT unit=3 to session`() throws {
        let json = """
        { "data": { "limits": [
          { "type": "CREDIT_LIMIT", "unit": 3, "percentage": 13 }
        ] } }
        """
        let snapshot = try ZaiUsageProbe.parseQuotaLimitResponse(Data(json.utf8), providerId: "zai")
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas.first?.quotaType == .session)
        #expect(snapshot.quotas.first?.percentRemaining == 87.0)
    }

    @Test
    func `maps CREDIT_LIMIT unit=6 to weekly`() throws {
        let json = """
        { "data": { "limits": [
          { "type": "CREDIT_LIMIT", "unit": 6, "percentage": 20 }
        ] } }
        """
        let snapshot = try ZaiUsageProbe.parseQuotaLimitResponse(Data(json.utf8), providerId: "zai")
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas.first?.quotaType == .weekly)
        #expect(snapshot.quotas.first?.percentRemaining == 80.0)
    }

    @Test
    func `preserves CREDIT_LIMIT with unknown unit rather than dropping it`() throws {
        let json = """
        { "data": { "limits": [
          { "type": "CREDIT_LIMIT", "unit": 99, "percentage": 5 }
        ] } }
        """
        let snapshot = try ZaiUsageProbe.parseQuotaLimitResponse(Data(json.utf8), providerId: "zai")
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas.first?.quotaType == .modelSpecific("Credits (unit 99)"))
    }

    @Test
    func `handles mixed TOKENS_LIMIT and CREDIT_LIMIT entries`() throws {
        let json = """
        { "data": { "limits": [
          { "type": "TOKENS_LIMIT", "unit": 3, "percentage": 13 },
          { "type": "CREDIT_LIMIT", "unit": 6, "percentage": 20 },
          { "type": "TIME_LIMIT", "unit": 5, "percentage": 1 }
        ] } }
        """
        let snapshot = try ZaiUsageProbe.parseQuotaLimitResponse(Data(json.utf8), providerId: "zai")
        #expect(snapshot.quotas.count == 3)
        #expect(snapshot.quotas.contains { $0.quotaType == .session })
        #expect(snapshot.quotas.contains { $0.quotaType == .weekly })
        #expect(snapshot.quotas.contains { $0.quotaType == .timeLimit("MCP") })
    }
}
