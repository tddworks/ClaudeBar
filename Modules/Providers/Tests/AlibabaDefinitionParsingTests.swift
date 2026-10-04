import Providers
import DataSources
import Testing
import Foundation
import Quotas

/// Alibaba's Coding Plan answer read by `alibaba-quota.js` — the old probe's
/// fixtures, quota for quota.
enum AlibabaDefinitionFixtures {
    static func parse(_ data: Data, providerId: String) throws -> UsageSnapshot {
        let definition = try Providers.builtIn("alibaba")
        let source = DataSources.make(definition.dataSource("api")!, providerId: providerId, scripts: Providers.builtInScripts,
                                      environment: { _ in nil })
        do { return try source.read(Response(body: data)) }
        catch let error as DataSourceError { throw error.reason }
    }
}

@Suite
struct AlibabaDefinitionParsingTests {

    // MARK: - Sample Data

    /// Full API response with all three quota windows
    static let sampleFullResponse = """
    {
      "code": "200",
      "data": {
        "codingPlanInstanceInfos": [
          {
            "planName": "Alibaba Coding Plan Pro",
            "status": "VALID",
            "codingPlanQuotaInfo": {
              "per5HourUsedQuota": 8,
              "per5HourTotalQuota": 100,
              "per5HourQuotaNextRefreshTime": "2026-03-12T19:17:15+08:00",
              "perWeekUsedQuota": 25,
              "perWeekTotalQuota": 500,
              "perWeekQuotaNextRefreshTime": "2026-03-15T00:00:00+08:00",
              "perBillMonthUsedQuota": 50,
              "perBillMonthTotalQuota": 2000,
              "perBillMonthQuotaNextRefreshTime": "2026-04-01T00:00:00+08:00"
            }
          }
        ]
      },
      "success": true
    }
    """

    /// Console RPC response wrapped in DataV2 envelope
    static let sampleConsoleRPCResponse = """
    {
      "code": "200",
      "data": {
        "DataV2": {
          "data": {
            "data": {
              "codingPlanInstanceInfos": [
                {
                  "planName": "Free Plan",
                  "status": "VALID",
                  "codingPlanQuotaInfo": {
                    "per5HourUsedQuota": 15,
                    "per5HourTotalQuota": 50,
                    "per5HourQuotaNextRefreshTime": "2026-03-12T20:00:00+08:00",
                    "perWeekUsedQuota": 100,
                    "perWeekTotalQuota": 300,
                    "perWeekQuotaNextRefreshTime": "2026-03-16T00:00:00+08:00",
                    "perBillMonthUsedQuota": 200,
                    "perBillMonthTotalQuota": 1000,
                    "perBillMonthQuotaNextRefreshTime": "2026-04-03T00:00:00+08:00"
                  }
                }
              ]
            }
          }
        }
      },
      "success": true
    }
    """

    /// Response with only 5-hour window (no weekly/monthly)
    static let samplePartialResponse = """
    {
      "code": "200",
      "data": {
        "codingPlanInstanceInfos": [
          {
            "planName": "Basic",
            "status": "VALID",
            "codingPlanQuotaInfo": {
              "per5HourUsedQuota": 3,
              "per5HourTotalQuota": 20
            }
          }
        ]
      },
      "success": true
    }
    """

    // MARK: - Full Response Parsing

    @Test
    func `parses three quota windows from full response`() throws {
        let data = Data(Self.sampleFullResponse.utf8)

        let snapshot = try AlibabaDefinitionFixtures.parse(data, providerId: "alibaba")

        #expect(snapshot.quotas.count == 3)
    }

    @Test
    func `maps session quota from 5-hour window`() throws {
        let data = Data(Self.sampleFullResponse.utf8)

        let snapshot = try AlibabaDefinitionFixtures.parse(data, providerId: "alibaba")

        let sessionQuota = snapshot.quota(for: .session)
        #expect(sessionQuota != nil)
        // remaining = (100 - 8) / 100 * 100 = 92%
        #expect(sessionQuota?.percentRemaining == 92.0)
    }

    @Test
    func `maps weekly quota from week window`() throws {
        let data = Data(Self.sampleFullResponse.utf8)

        let snapshot = try AlibabaDefinitionFixtures.parse(data, providerId: "alibaba")

        let weeklyQuota = snapshot.quota(for: .weekly)
        #expect(weeklyQuota != nil)
        // remaining = (500 - 25) / 500 * 100 = 95%
        #expect(weeklyQuota?.percentRemaining == 95.0)
    }

    @Test
    func `maps monthly quota as timeLimit`() throws {
        let data = Data(Self.sampleFullResponse.utf8)

        let snapshot = try AlibabaDefinitionFixtures.parse(data, providerId: "alibaba")

        let monthlyQuota = snapshot.quota(for: .timeLimit("Monthly"))
        #expect(monthlyQuota != nil)
        // remaining = (2000 - 50) / 2000 * 100 = 97.5%
        #expect(monthlyQuota?.percentRemaining == 97.5)
    }

    @Test
    func `parses reset times from ISO-8601 dates`() throws {
        let data = Data(Self.sampleFullResponse.utf8)

        let snapshot = try AlibabaDefinitionFixtures.parse(data, providerId: "alibaba")

        let sessionQuota = snapshot.quota(for: .session)
        #expect(sessionQuota?.resetsAt != nil)

        let weeklyQuota = snapshot.quota(for: .weekly)
        #expect(weeklyQuota?.resetsAt != nil)

        let monthlyQuota = snapshot.quota(for: .timeLimit("Monthly"))
        #expect(monthlyQuota?.resetsAt != nil)
    }

    @Test
    func `extracts plan name as loginMethod`() throws {
        let data = Data(Self.sampleFullResponse.utf8)

        let snapshot = try AlibabaDefinitionFixtures.parse(data, providerId: "alibaba")

        #expect(snapshot.loginMethod == "Alibaba Coding Plan Pro")
    }

    @Test
    func `sets providerId correctly`() throws {
        let data = Data(Self.sampleFullResponse.utf8)

        let snapshot = try AlibabaDefinitionFixtures.parse(data, providerId: "alibaba")

        #expect(snapshot.providerId == "alibaba")
        #expect(snapshot.quotas.allSatisfy { $0.providerId == "alibaba" })
    }

    // MARK: - Console RPC (DataV2 envelope) Parsing

    @Test
    func `parses nested DataV2 console RPC response`() throws {
        let data = Data(Self.sampleConsoleRPCResponse.utf8)

        let snapshot = try AlibabaDefinitionFixtures.parse(data, providerId: "alibaba")

        #expect(snapshot.quotas.count == 3)

        let sessionQuota = snapshot.quota(for: .session)
        // remaining = (50 - 15) / 50 * 100 = 70%
        #expect(sessionQuota?.percentRemaining == 70.0)
    }

    // MARK: - Partial Response

    @Test
    func `handles response with only 5-hour window`() throws {
        let data = Data(Self.samplePartialResponse.utf8)

        let snapshot = try AlibabaDefinitionFixtures.parse(data, providerId: "alibaba")

        #expect(snapshot.quotas.count == 1)
        let sessionQuota = snapshot.quota(for: .session)
        // remaining = (20 - 3) / 20 * 100 = 85%
        #expect(sessionQuota?.percentRemaining == 85.0)
    }

    // MARK: - Edge Cases

    @Test
    func `caps percent remaining at 100 when used is 0`() throws {
        let response = """
        {
          "code": "200",
          "data": {
            "codingPlanInstanceInfos": [
              {
                "status": "VALID",
                "codingPlanQuotaInfo": {
                  "per5HourUsedQuota": 0,
                  "per5HourTotalQuota": 100
                }
              }
            ]
          },
          "success": true
        }
        """
        let data = Data(response.utf8)

        let snapshot = try AlibabaDefinitionFixtures.parse(data, providerId: "alibaba")

        #expect(snapshot.quota(for: .session)?.percentRemaining == 100.0)
    }

    @Test
    func `handles fully used quota with 0 percent remaining`() throws {
        let response = """
        {
          "code": "200",
          "data": {
            "codingPlanInstanceInfos": [
              {
                "status": "VALID",
                "codingPlanQuotaInfo": {
                  "per5HourUsedQuota": 100,
                  "per5HourTotalQuota": 100
                }
              }
            ]
          },
          "success": true
        }
        """
        let data = Data(response.utf8)

        let snapshot = try AlibabaDefinitionFixtures.parse(data, providerId: "alibaba")

        #expect(snapshot.quota(for: .session)?.percentRemaining == 0.0)
    }

    @Test
    func `generates reset text from used and total`() throws {
        let data = Data(Self.sampleFullResponse.utf8)

        let snapshot = try AlibabaDefinitionFixtures.parse(data, providerId: "alibaba")

        let sessionQuota = snapshot.quota(for: .session)
        #expect(sessionQuota?.resetText == "8 / 100 used")
    }

    // MARK: - Error Handling

    @Test
    func `throws parseFailed for invalid JSON`() throws {
        let data = Data("not json".utf8)

        #expect(throws: UsageError.self) {
            try AlibabaDefinitionFixtures.parse(data, providerId: "alibaba")
        }
    }

    @Test
    func `throws parseFailed for empty response`() throws {
        let data = Data("{}".utf8)

        #expect(throws: UsageError.self) {
            try AlibabaDefinitionFixtures.parse(data, providerId: "alibaba")
        }
    }

    @Test
    func `throws sessionExpired for login required response`() throws {
        let response = """
        {
          "code": "ConsoleNeedLogin",
          "message": "Please log in first"
        }
        """
        let data = Data(response.utf8)

        #expect(throws: UsageError.sessionExpired()) {
            try AlibabaDefinitionFixtures.parse(data, providerId: "alibaba")
        }
    }

    @Test
    func `throws authenticationRequired for 401 status code`() throws {
        let response = """
        {
          "statusCode": 401,
          "message": "Unauthorized"
        }
        """
        let data = Data(response.utf8)

        #expect(throws: UsageError.authenticationRequired) {
            try AlibabaDefinitionFixtures.parse(data, providerId: "alibaba")
        }
    }

    @Test
    func `skips expired plan instances`() throws {
        let response = """
        {
          "code": "200",
          "data": {
            "codingPlanInstanceInfos": [
              {
                "planName": "Expired Plan",
                "status": "EXPIRED",
                "codingPlanQuotaInfo": {
                  "per5HourUsedQuota": 0,
                  "per5HourTotalQuota": 100
                }
              },
              {
                "planName": "Active Plan",
                "status": "VALID",
                "codingPlanQuotaInfo": {
                  "per5HourUsedQuota": 10,
                  "per5HourTotalQuota": 100
                }
              }
            ]
          },
          "success": true
        }
        """
        let data = Data(response.utf8)

        let snapshot = try AlibabaDefinitionFixtures.parse(data, providerId: "alibaba")

        #expect(snapshot.loginMethod == "Active Plan")
        #expect(snapshot.quota(for: .session)?.percentRemaining == 90.0)
    }
}
