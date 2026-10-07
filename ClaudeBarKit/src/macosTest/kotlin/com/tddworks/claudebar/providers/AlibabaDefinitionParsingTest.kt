package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageError
import com.tddworks.claudebar.quotas.UsageSnapshot
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/** Alibaba's Coding Plan answer read by `alibaba-quota.js` — the old probe's fixtures, quota for quota. */
internal object AlibabaDefinitionFixtures {
    fun parse(json: String, providerId: String): UsageSnapshot =
        RepoDefinitions.read("alibaba", "api", Response(body = json.encodeToByteArray()), providerId)
}

class AlibabaDefinitionParsingTest {
    private companion object {
        /** Full API response with all three quota windows. */
        val sampleFullResponse = """
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

        /** Console RPC response wrapped in DataV2 envelope. */
        val sampleConsoleRPCResponse = """
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

        /** Response with only 5-hour window (no weekly/monthly). */
        val samplePartialResponse = """
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
    }

    // Full response

    @Test
    fun `should show three quotas when Alibaba reports all three windows`() {
        val snapshot = AlibabaDefinitionFixtures.parse(sampleFullResponse, "alibaba")

        assertEquals(3, snapshot.quotas.size)
    }

    @Test
    fun `should show the 5-hour window as the session with 92 percent left`() {
        val snapshot = AlibabaDefinitionFixtures.parse(sampleFullResponse, "alibaba")

        // remaining = (100 - 8) / 100 * 100 = 92%
        assertEquals(92.0, assertNotNull(snapshot.quota(QuotaType.Session)).percentRemaining)
    }

    @Test
    fun `should show the week window as weekly with 95 percent left`() {
        val snapshot = AlibabaDefinitionFixtures.parse(sampleFullResponse, "alibaba")

        // remaining = (500 - 25) / 500 * 100 = 95%
        assertEquals(95.0, assertNotNull(snapshot.quota(QuotaType.Weekly)).percentRemaining)
    }

    @Test
    fun `should show the billing month as a Monthly quota with 97 point 5 percent left`() {
        val snapshot = AlibabaDefinitionFixtures.parse(sampleFullResponse, "alibaba")

        // remaining = (2000 - 50) / 2000 * 100 = 97.5%
        assertEquals(97.5, assertNotNull(snapshot.quota(QuotaType.TimeLimit("Monthly"))).percentRemaining)
    }

    @Test
    fun `should show when each window resets`() {
        val snapshot = AlibabaDefinitionFixtures.parse(sampleFullResponse, "alibaba")

        assertNotNull(snapshot.quota(QuotaType.Session)?.resetsAtSeconds)
        assertNotNull(snapshot.quota(QuotaType.Weekly)?.resetsAtSeconds)
        assertNotNull(snapshot.quota(QuotaType.TimeLimit("Monthly"))?.resetsAtSeconds)
    }

    @Test
    fun `should show the plan's name as how the person signed in`() {
        val snapshot = AlibabaDefinitionFixtures.parse(sampleFullResponse, "alibaba")

        assertEquals("Alibaba Coding Plan Pro", snapshot.loginMethod)
    }

    @Test
    fun `should tag the usage and every quota as Alibaba's`() {
        val snapshot = AlibabaDefinitionFixtures.parse(sampleFullResponse, "alibaba")

        assertEquals("alibaba", snapshot.providerId)
        assertTrue(snapshot.quotas.all { it.providerId == "alibaba" })
    }

    // Console RPC (DataV2 envelope)

    @Test
    fun `should show the quotas when the console answers inside its envelope`() {
        val snapshot = AlibabaDefinitionFixtures.parse(sampleConsoleRPCResponse, "alibaba")

        assertEquals(3, snapshot.quotas.size)
        // remaining = (50 - 15) / 50 * 100 = 70%
        assertEquals(70.0, snapshot.quota(QuotaType.Session)?.percentRemaining)
    }

    // Partial response

    @Test
    fun `should show only the session when Alibaba reports only the 5-hour window`() {
        val snapshot = AlibabaDefinitionFixtures.parse(samplePartialResponse, "alibaba")

        assertEquals(1, snapshot.quotas.size)
        // remaining = (20 - 3) / 20 * 100 = 85%
        assertEquals(85.0, snapshot.quota(QuotaType.Session)?.percentRemaining)
    }

    // Edge cases

    @Test
    fun `should show 100 percent left when nothing is used`() {
        val response = """
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

        val snapshot = AlibabaDefinitionFixtures.parse(response, "alibaba")

        assertEquals(100.0, snapshot.quota(QuotaType.Session)?.percentRemaining)
    }

    @Test
    fun `should show 0 percent left when the quota is fully used`() {
        val response = """
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

        val snapshot = AlibabaDefinitionFixtures.parse(response, "alibaba")

        assertEquals(0.0, snapshot.quota(QuotaType.Session)?.percentRemaining)
    }

    @Test
    fun `should say how much of the total is used as 8 of 100`() {
        val snapshot = AlibabaDefinitionFixtures.parse(sampleFullResponse, "alibaba")

        assertEquals("8 / 100 used", snapshot.quota(QuotaType.Session)?.resetText)
    }

    // Errors

    @Test
    fun `should fail when Alibaba's answer is not JSON`() {
        assertFailsWith<UsageError> { AlibabaDefinitionFixtures.parse("not json", "alibaba") }
    }

    @Test
    fun `should fail when Alibaba's answer is empty`() {
        assertFailsWith<UsageError> { AlibabaDefinitionFixtures.parse("{}", "alibaba") }
    }

    @Test
    fun `should say the session expired when the console asks to log in`() {
        val response = """
        {
          "code": "ConsoleNeedLogin",
          "message": "Please log in first"
        }
        """

        val error = assertFailsWith<UsageError> { AlibabaDefinitionFixtures.parse(response, "alibaba") }
        assertEquals(UsageError.SessionExpired(), error)
    }

    @Test
    fun `should ask to sign in when Alibaba answers 401`() {
        val response = """
        {
          "statusCode": 401,
          "message": "Unauthorized"
        }
        """

        val error = assertFailsWith<UsageError> { AlibabaDefinitionFixtures.parse(response, "alibaba") }
        assertEquals(UsageError.AuthenticationRequired, error)
    }

    @Test
    fun `should show the active plan and not one that has expired`() {
        val response = """
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

        val snapshot = AlibabaDefinitionFixtures.parse(response, "alibaba")

        assertEquals("Active Plan", snapshot.loginMethod)
        assertEquals(90.0, snapshot.quota(QuotaType.Session)?.percentRemaining)
    }
}
