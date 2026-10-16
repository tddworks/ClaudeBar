import DataSources
import Foundation
import Providers
import Quotas
import Testing

/// Z.ai as data: the quota-limit response read by `zai-usage.js` — the old
/// probe's fixtures, quota for quota.
@Suite
struct ZaiDefinitionTests {

    private func read(_ data: Data, providerId: String) throws -> UsageSnapshot {
        let definition = try ProviderFactory.builtIn("zai")
        let source = DataSources.make(definition.dataSources[0], providerId: providerId, scripts: ProviderFactory.builtInScripts, environment: { _ in nil })
        do { return try source.read(Response(body: data)) }
        catch let error as DataSourceError { throw error.reason }
    }

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
    func `should show a quota for each limit Z.ai reports`() throws {
        // Given
        let data = Data(Self.sampleQuotaLimitResponse.utf8)

        // When
        let snapshot = try read(data, providerId: "zai")

        // Then
        #expect(snapshot.quotas.count == 2)
    }

    @Test
    func `should show 35% of the session left when Z.ai reports 65% of tokens used`() throws {
        // Given
        let data = Data(Self.sampleQuotaLimitResponse.utf8)

        // When
        let snapshot = try read(data, providerId: "zai")

        // Then - percentage is "used", so remaining = 100 - used
        let tokenQuota = snapshot.quotas.first { $0.quotaType == .session }
        #expect(tokenQuota != nil)
        #expect(tokenQuota?.percentRemaining == 35.0) // 100 - 65 = 35
    }

    @Test
    func `should show the token limit as the session`() throws {
        // Given
        let data = Data(Self.sampleQuotaLimitResponse.utf8)

        // When
        let snapshot = try read(data, providerId: "zai")

        // Then
        let tokenQuota = snapshot.quotas.first { $0.quotaType == .session }
        #expect(tokenQuota != nil)
    }

    @Test
    func `should show the time limit as the MCP quota, with 70% left when 30% is used`() throws {
        // Given
        let data = Data(Self.sampleQuotaLimitResponse.utf8)

        // When
        let snapshot = try read(data, providerId: "zai")

        // Then
        let timeQuota = snapshot.quotas.first { $0.quotaType == .timeLimit("MCP") }
        #expect(timeQuota != nil)
        #expect(timeQuota?.percentRemaining == 70.0) // 100 - 30 = 70
    }

    @Test
    func `should show only the session when Z.ai reports only a token limit`() throws {
        // Given
        let data = Data(Self.sampleQuotaLimitResponseOnlyTokens.utf8)

        // When
        let snapshot = try read(data, providerId: "zai")

        // Then
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas.first?.quotaType == .session)
        #expect(snapshot.quotas.first?.percentRemaining == 55.0) // 100 - 45 = 55
    }

    @Test
    func `should report every quota as Z.ai's`() throws {
        // Given
        let data = Data(Self.sampleQuotaLimitResponse.utf8)

        // When
        let snapshot = try read(data, providerId: "zai")

        // Then
        #expect(snapshot.providerId == "zai")
        #expect(snapshot.quotas.allSatisfy { $0.providerId == "zai" })
    }

    @Test
    func `should show nothing left when Z.ai reports 100% used`() throws {
        // Given
        let data = Data(Self.sampleQuotaLimitResponseFullUsage.utf8)

        // When
        let snapshot = try read(data, providerId: "zai")

        // Then
        #expect(snapshot.quotas.first?.percentRemaining == 0.0)
    }

    @Test
    func `should show everything left when Z.ai reports 0% used`() throws {
        // Given
        let data = Data(Self.sampleQuotaLimitResponseNoUsage.utf8)

        // When
        let snapshot = try read(data, providerId: "zai")

        // Then
        #expect(snapshot.quotas.first?.percentRemaining == 100.0)
    }

    // MARK: - Error Handling Tests

    @Test
    func `should fail to read usage when Z.ai answers with something that is not JSON`() throws {
        // Given
        let invalidData = Data("not json".utf8)

        // When/Then
        #expect(throws: UsageError.self) {
            try read(invalidData, providerId: "zai")
        }
    }

    @Test
    func `should fail to read usage when Z.ai reports no limits`() throws {
        // Given
        let data = Data(Self.sampleQuotaLimitResponseEmpty.utf8)

        // When/Then
        #expect(throws: UsageError.self) {
            try read(data, providerId: "zai")
        }
    }

    @Test
    func `should fail to read usage when Z.ai answers with an error instead of usage`() throws {
        // Given
        let responseWithoutData = """
        {
          "error": "Unauthorized"
        }
        """
        let data = Data(responseWithoutData.utf8)

        // When/Then
        #expect(throws: UsageError.self) {
            try read(data, providerId: "zai")
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
    func `should show the session, the weekly quota and MCP when Z.ai reports all three`() throws {
        let data = Data(Self.sampleQuotaLimitResponseRealZai.utf8)
        let snapshot = try read(data, providerId: "zai")

        #expect(snapshot.quotas.count == 3)
        #expect(snapshot.quotas.contains { $0.quotaType == .session })
        #expect(snapshot.quotas.contains { $0.quotaType == .weekly })
        #expect(snapshot.quotas.contains { $0.quotaType == .timeLimit("MCP") })
    }

    @Test
    func `should show a 5-hour token limit as the session (unit 3)`() throws {
        let json = """
        { "data": { "limits": [
          { "type": "TOKENS_LIMIT", "unit": 3, "percentage": 13 }
        ] } }
        """
        let snapshot = try read(Data(json.utf8), providerId: "zai")
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas.first?.quotaType == .session)
        #expect(snapshot.quotas.first?.percentRemaining == 87.0)
    }

    @Test
    func `should show a 7-day token limit as the weekly quota (unit 6)`() throws {
        let json = """
        { "data": { "limits": [
          { "type": "TOKENS_LIMIT", "unit": 6, "percentage": 46 }
        ] } }
        """
        let snapshot = try read(Data(json.utf8), providerId: "zai")
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas.first?.quotaType == .weekly)
        #expect(snapshot.quotas.first?.percentRemaining == 54.0)
    }

    @Test
    func `should show the session and the weekly quota apart when Z.ai reports two token limits`() throws {
        // Regression test: prior implementation mapped both TOKENS_LIMIT entries
        // to .session, so the second one (weekly) was effectively hidden.
        let data = Data(Self.sampleQuotaLimitResponseRealZai.utf8)
        let snapshot = try read(data, providerId: "zai")

        let sessionQuotas = snapshot.quotas.filter { $0.quotaType == .session }
        let weeklyQuotas = snapshot.quotas.filter { $0.quotaType == .weekly }
        #expect(sessionQuotas.count == 1)
        #expect(weeklyQuotas.count == 1)
        #expect(sessionQuotas.first?.percentRemaining != weeklyQuotas.first?.percentRemaining)
    }

    @Test
    func `should show a token limit with no window as the session`() throws {
        // Existing tests use payloads without `unit` — preserve original behavior.
        let json = """
        { "data": { "limits": [
          { "type": "TOKENS_LIMIT", "percentage": 65 }
        ] } }
        """
        let snapshot = try read(Data(json.utf8), providerId: "zai")
        #expect(snapshot.quotas.first?.quotaType == .session)
    }

    @Test
    func `should still show a token limit whose window is unknown, named by its unit`() throws {
        let json = """
        { "data": { "limits": [
          { "type": "TOKENS_LIMIT", "unit": 99, "percentage": 25 }
        ] } }
        """
        let snapshot = try read(Data(json.utf8), providerId: "zai")
        #expect(snapshot.quotas.count == 1)
        if case .modelSpecific(let label) = snapshot.quotas.first?.quotaType {
            #expect(label.contains("99"))
        } else {
            Issue.record("Expected .modelSpecific quota type for unknown unit, got \(String(describing: snapshot.quotas.first?.quotaType))")
        }
    }

    @Test
    func `should show all left for a negative usage and none left past 100% when Z.ai reports an out-of-range percentage`() throws {
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
        let snapshot = try read(data, providerId: "zai")

        // Then - should clamp to 0-100 range
        #expect(snapshot.quotas.count == 2)
        #expect(snapshot.quotas[0].percentRemaining == 100)
        #expect(snapshot.quotas[1].percentRemaining == 0)
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
    func `should show the session and the weekly quota when the plan counts credits`() throws {
        let data = Data(Self.sampleQuotaLimitResponseCreditPlan.utf8)
        let snapshot = try read(data, providerId: "zai")

        #expect(snapshot.quotas.count == 2)
        #expect(snapshot.quotas.contains { $0.quotaType == .session })
        #expect(snapshot.quotas.contains { $0.quotaType == .weekly })
    }

    @Test
    func `should show a 5-hour credit limit as the session (unit 3)`() throws {
        let json = """
        { "data": { "limits": [
          { "type": "CREDIT_LIMIT", "unit": 3, "percentage": 13 }
        ] } }
        """
        let snapshot = try read(Data(json.utf8), providerId: "zai")
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas.first?.quotaType == .session)
        #expect(snapshot.quotas.first?.percentRemaining == 87.0)
    }

    @Test
    func `should show a 7-day credit limit as the weekly quota (unit 6)`() throws {
        let json = """
        { "data": { "limits": [
          { "type": "CREDIT_LIMIT", "unit": 6, "percentage": 20 }
        ] } }
        """
        let snapshot = try read(Data(json.utf8), providerId: "zai")
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas.first?.quotaType == .weekly)
        #expect(snapshot.quotas.first?.percentRemaining == 80.0)
    }

    @Test
    func `should still show a credit limit whose window is unknown, named by its unit`() throws {
        let json = """
        { "data": { "limits": [
          { "type": "CREDIT_LIMIT", "unit": 99, "percentage": 5 }
        ] } }
        """
        let snapshot = try read(Data(json.utf8), providerId: "zai")
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas.first?.quotaType == .modelSpecific("Credits (unit 99)"))
    }

    @Test
    func `should show the session, the weekly quota and MCP when Z.ai mixes token and credit limits`() throws {
        let json = """
        { "data": { "limits": [
          { "type": "TOKENS_LIMIT", "unit": 3, "percentage": 13 },
          { "type": "CREDIT_LIMIT", "unit": 6, "percentage": 20 },
          { "type": "TIME_LIMIT", "unit": 5, "percentage": 1 }
        ] } }
        """
        let snapshot = try read(Data(json.utf8), providerId: "zai")
        #expect(snapshot.quotas.count == 3)
        #expect(snapshot.quotas.contains { $0.quotaType == .session })
        #expect(snapshot.quotas.contains { $0.quotaType == .weekly })
        #expect(snapshot.quotas.contains { $0.quotaType == .timeLimit("MCP") })
    }
}
