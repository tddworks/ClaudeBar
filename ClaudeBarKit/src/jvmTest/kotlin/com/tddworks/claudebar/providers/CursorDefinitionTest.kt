package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.AnsweringTransport
import com.tddworks.claudebar.datasources.DEDICATED_FOLDER
import com.tddworks.claudebar.datasources.DataSources
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.datasources.lookup.FakeCookies
import com.tddworks.claudebar.datasources.lookup.FakeDatabase
import com.tddworks.claudebar.datasources.lookup.FakeSecurity
import com.tddworks.claudebar.datasources.lookup.FakeStorage
import com.tddworks.claudebar.datasources.lookup.SecurityResult
import com.tddworks.claudebar.datasources.lookup.StoredValue
import com.tddworks.claudebar.datasources.mapping.GraalScriptEngine
import com.tddworks.claudebar.datasources.process.DiskFiles
import com.tddworks.claudebar.datasources.process.FakeCLIExecutor
import com.tddworks.claudebar.datasources.process.InMemoryLoginFolders
import com.tddworks.claudebar.datasources.process.RPCTransportFactory
import com.tddworks.claudebar.quotas.AccountTier
import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageError
import com.tddworks.claudebar.quotas.UsageSnapshot
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.Arguments
import org.junit.jupiter.params.provider.MethodSource
import org.junit.jupiter.params.provider.ValueSource
import java.io.File
import java.nio.file.Files
import java.util.Base64
import kotlin.math.abs

private fun <T> required(value: T?): T {
    assertNotNull(value)
    return value!!
}

/**
 * Cursor as data: the Cursor app's own login read from its database (or an added account's saved
 * token), the user id taken from the token's `sub` claim, and `cursor-usage.js` — the old probe's
 * responses, quota for quota.
 */
class CursorDefinitionTest {
    private val stubs = mutableListOf<StubbedProvider>()

    /** What a request broke of what Cursor expects — checked once each test is done. */
    private val problems = mutableListOf<String>()

    @AfterEach
    fun cleanUp() {
        stubs.forEach { it.cleanUp() }
        assertEquals(emptyList<String>(), problems)
    }

    /** The Cookie header Cursor was last sent. */
    private class CookieCapture {
        @Volatile var cookie: String? = null
    }

    /** Adds a login by its token, then refreshes it — asked of its provider. */
    private fun refreshAdded(data: String, token: String, capture: CookieCapture = CookieCapture()): RefreshOutcome {
        val vault = MemoryVault()
        val network = StubNetwork { call ->
            if (call.url != "https://cursor.com/api/usage-summary") problems += "url ${call.url}"
            if (call.method != "GET" || call.timeoutSeconds != 15.0) problems += "${call.method} ${call.timeoutSeconds}"
            capture.cookie = call.headers.entries.firstOrNull { it.key.equals("Cookie", true) }?.value
            Response(200, body = data.encodeToByteArray())
        }
        val stub = StubbedProvider(network = network).also { stubs += it }
        val provider = stub.make(TestDefinitions.builtIn("cursor"), vault = vault, settings = InMemoryProviderSettings())
        val added = provider.accounts.add(filling = mapOf("accessToken" to token)).done()
        return provider.refreshNow(added)
    }

    private fun parse(data: String): UsageSnapshot = refreshAdded(data, "header.eyJzdWIiOiJmaXh0dXJlLXVzZXIifQ.signature").usage()

    private fun userID(token: String): String {
        val capture = CookieCapture()
        refreshAdded("""{"isUnlimited":true}""", token, capture)
        val cookie = required(capture.cookie)
        assertTrue(cookie.startsWith("WorkosCursorSessionToken="))
        assertTrue(cookie.endsWith("::$token"))
        return cookie.drop("WorkosCursorSessionToken=".length).dropLast(token.length + 2)
    }


    // Real API Response

    @Test
    fun `should show an Ultra plan's monthly requests, then its Auto and API pools on the billing cycle`() {
        // Actual response from cursor.com/api/usage-summary
        val json = """
        {
            "billingCycleStart": "2026-02-06T03:34:49.000Z",
            "billingCycleEnd": "2026-03-06T03:34:49.000Z",
            "membershipType": "ultra",
            "limitType": "user",
            "isUnlimited": false,
            "autoModelSelectedDisplayMessage": "You've used 1% of your included total usage",
            "namedModelSelectedDisplayMessage": "You've used 1% of your included API usage",
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 326,
                    "limit": 40000,
                    "remaining": 39674,
                    "breakdown": { "included": 40000, "bonus": 0, "total": 40000 },
                    "autoPercentUsed": 0.033,
                    "apiPercentUsed": 0.586,
                    "totalPercentUsed": 0.815
                },
                "onDemand": {
                    "enabled": false,
                    "used": 0,
                    "limit": null,
                    "remaining": null
                }
            },
            "teamUsage": {}
        }
        """

        val snapshot = parse(json)

        assertTrue(snapshot.providerId.startsWith("cursor."))
        assertEquals(3, snapshot.quotas.size)
        assertEquals(AccountTier.Custom("ULTRA"), snapshot.accountTier)

        val monthly = snapshot.quotas[0]
        assertEquals(QuotaType.TimeLimit("Monthly"), monthly.quotaType)
        assertEquals("time:Monthly", monthly.quotaType.quotaKey)
        assertTrue(abs(monthly.percentRemaining - 99.185) < 0.01)
        assertEquals("326/40000 requests", monthly.resetText)
        assertNotNull(monthly.resetsAtSeconds)
        assertNull(monthly.windowSeconds)

        val auto = snapshot.quotas[1]
        assertEquals(QuotaType.TimeLimit("Auto"), auto.quotaType)
        assertTrue(abs(auto.percentRemaining - 99.967) < 0.01)
        assertNull(auto.resetText)
        assertEquals(monthly.resetsAtSeconds, auto.resetsAtSeconds)
        assertEquals(28.0 * 24 * 3600, auto.windowSeconds)

        val api = snapshot.quotas[2]
        assertEquals(QuotaType.TimeLimit("API"), api.quotaType)
        assertTrue(abs(api.percentRemaining - 99.414) < 0.01)
        assertNull(api.resetText)
        assertEquals(monthly.resetsAtSeconds, api.resetsAtSeconds)
        assertEquals(28.0 * 24 * 3600, api.windowSeconds)
    }

    // Plan Usage

    @Test
    fun `should show a Pro plan's monthly requests used out of its limit`() {
        val json = """
        {
            "membershipType": "pro",
            "billingCycleEnd": "2025-02-01T00:00:00Z",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 123,
                    "limit": 500,
                    "remaining": 377
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """

        val snapshot = parse(json)

        assertTrue(snapshot.providerId.startsWith("cursor."))
        assertEquals(1, snapshot.quotas.size)
        assertEquals(AccountTier.Custom("PRO"), snapshot.accountTier)

        val quota = snapshot.quotas[0]
        assertEquals(QuotaType.TimeLimit("Monthly"), quota.quotaType)
        assertTrue(abs(quota.percentRemaining - 75.4) < 0.1)
        assertEquals("123/500 requests", quota.resetText)
        assertNotNull(quota.resetsAtSeconds)
    }

    @Test
    fun `should show on-demand spend beside the monthly requests when on-demand is enabled`() {
        val json = """
        {
            "membershipType": "pro",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 400,
                    "limit": 500,
                    "remaining": 100
                },
                "onDemand": {
                    "enabled": true,
                    "used": 25,
                    "limit": 100,
                    "remaining": 75
                }
            }
        }
        """

        val snapshot = parse(json)

        assertEquals(2, snapshot.quotas.size)

        val plan = snapshot.quotas.firstOrNull { it.quotaType == QuotaType.TimeLimit("Monthly") }
        assertNotNull(plan)
        assertTrue(abs(plan!!.percentRemaining - 20.0) < 0.1)
        assertEquals("400/500 requests", plan!!.resetText)

        val onDemand = snapshot.quotas.firstOrNull { it.quotaType == QuotaType.TimeLimit("On-Demand") }
        assertNotNull(onDemand)
        assertTrue(abs(onDemand!!.percentRemaining - 75.0) < 0.1)
    }

    @Test
    fun `should show no requests left when the plan is used up`() {
        val json = """
        {
            "membershipType": "pro",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 500,
                    "limit": 500,
                    "remaining": 0
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """

        val snapshot = parse(json)

        assertEquals(1, snapshot.quotas.size)
        assertEquals(0.0, snapshot.quotas[0].percentRemaining)
        assertEquals("500/500 requests", snapshot.quotas[0].resetText)
    }

    @Test
    fun `should measure a Pro plan with bonus credits against its whole capacity, not show it empty`() {
        // Regression: a Pro user with bonus credits. The `used`/`limit` fields describe
        // only the *included* base (2000/2000 = maxed), but `breakdown.total` shows the
        // real capacity (9770 incl. 7770 bonus) and `totalPercentUsed` shows true usage
        // (28.32%). The old logic derived percentRemaining from used/limit -> 0% -> EMPTY.
        // Correct behavior: ~71.68% remaining, NOT depleted.
        val json = """
        {
            "billingCycleStart": "2026-06-25T03:47:17.000Z",
            "billingCycleEnd": "2026-07-25T03:47:17.000Z",
            "membershipType": "pro",
            "limitType": "user",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 2000,
                    "limit": 2000,
                    "remaining": 0,
                    "breakdown": { "included": 2000, "bonus": 7770, "total": 9770 },
                    "autoPercentUsed": 23.05,
                    "apiPercentUsed": 63.44,
                    "totalPercentUsed": 28.32
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            },
            "teamUsage": {}
        }
        """

        val snapshot = parse(json)

        assertEquals(3, snapshot.quotas.size)
        val monthly = snapshot.quotas[0]
        assertEquals(QuotaType.TimeLimit("Monthly"), monthly.quotaType)
        // 28.32% used of the full 9770 capacity -> 71.68% remaining (was incorrectly 0)
        assertTrue(abs(monthly.percentRemaining - 71.68) < 0.1)
        assertEquals("2767/9770 requests", monthly.resetText)
        assertNotNull(monthly.resetsAtSeconds)
        assertNull(monthly.windowSeconds)

        val auto = snapshot.quotas[1]
        assertEquals(QuotaType.TimeLimit("Auto"), auto.quotaType)
        assertTrue(abs(auto.percentRemaining - 76.95) < 0.1)
        assertNull(auto.resetText)
        assertEquals(monthly.resetsAtSeconds, auto.resetsAtSeconds)
        assertEquals(30.0 * 24 * 3600, auto.windowSeconds)

        val api = snapshot.quotas[2]
        assertEquals(QuotaType.TimeLimit("API"), api.quotaType)
        assertTrue(abs(api.percentRemaining - 36.56) < 0.1)
        assertNull(api.resetText)
        assertEquals(30.0 * 24 * 3600, api.windowSeconds)
    }

    @Test
    fun `should show no requests left, not below zero, when usage is over the limit`() {
        val json = """
        {
            "membershipType": "pro",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 550,
                    "limit": 500,
                    "remaining": -50
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """

        val snapshot = parse(json)

        assertEquals(1, snapshot.quotas.size)
        assertEquals(0.0, snapshot.quotas[0].percentRemaining)
    }

    // Unlimited & Special Cases

    @Test
    fun `should show the plan and no made-up 100% when the plan is unlimited`() {
        val json = """
        {
            "membershipType": "business",
            "isUnlimited": true,
            "individualUsage": {
                "plan": { "enabled": false },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """

        val snapshot = parse(json)

        // No ceiling, so no quota — the plan, and no made-up 100% (the Left law).
        assertTrue(snapshot.quotas.isEmpty())
        assertEquals(AccountTier.Custom("BUSINESS"), snapshot.accountTier)
    }

    @Test
    fun `should show a free plan's monthly requests left`() {
        val json = """
        {
            "membershipType": "free",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 30,
                    "limit": 50,
                    "remaining": 20
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """

        val snapshot = parse(json)

        assertEquals(AccountTier.Custom("FREE"), snapshot.accountTier)
        assertEquals(1, snapshot.quotas.size)
        assertTrue(abs(snapshot.quotas[0].percentRemaining - 40.0) < 0.1)
    }

    // Enterprise Plan

    @Test
    fun `should show an Enterprise plan's monthly, Auto and API pools and the team's on-demand credits`() {
        val json = """
        {
            "billingCycleStart": "2026-03-01T00:00:00.000Z",
            "billingCycleEnd": "2026-04-01T00:00:00.000Z",
            "membershipType": "enterprise",
            "limitType": "team",
            "isUnlimited": false,
            "autoModelSelectedDisplayMessage": "You've used 7% of your included total usage",
            "namedModelSelectedDisplayMessage": "You've used 7% of your included API usage",
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 0,
                    "limit": 0,
                    "remaining": 0,
                    "breakdown": {
                        "included": 0,
                        "bonus": 300,
                        "total": 300
                    },
                    "autoPercentUsed": 0,
                    "apiPercentUsed": 6.9,
                    "totalPercentUsed": 6.9
                },
                "onDemand": {
                    "enabled": false,
                    "used": 0,
                    "limit": 0,
                    "remaining": 0
                }
            },
            "teamUsage": {
                "onDemand": {
                    "enabled": true,
                    "used": 0,
                    "limit": 10000,
                    "remaining": 10000
                }
            }
        }
        """

        val snapshot = parse(json)

        assertTrue(snapshot.providerId.startsWith("cursor."))
        assertEquals(AccountTier.Custom("ENTERPRISE"), snapshot.accountTier)

        // Monthly + Auto (integer 0) + API + team on-demand
        assertEquals(4, snapshot.quotas.size)
        assertEquals(
            listOf(QuotaType.TimeLimit("Monthly"), QuotaType.TimeLimit("Auto"), QuotaType.TimeLimit("API"), QuotaType.TimeLimit("Team")),
            snapshot.quotas.map { it.quotaType },
        )

        val monthly = snapshot.quotas[0]
        // 6.9% used of 300 -> ~93.1% remaining
        assertTrue(abs(monthly.percentRemaining - 93.1) < 0.5)
        assertNotNull(monthly.resetText)
        assertNull(monthly.windowSeconds)

        val auto = snapshot.quotas[1]
        assertEquals(100.0, auto.percentRemaining)
        assertNull(auto.resetText)
        assertEquals(monthly.resetsAtSeconds, auto.resetsAtSeconds)
        assertEquals(31.0 * 24 * 3600, auto.windowSeconds)

        val api = snapshot.quotas[2]
        assertTrue(abs(api.percentRemaining - 93.1) < 0.5)
        assertNull(api.resetText)
        assertEquals(31.0 * 24 * 3600, api.windowSeconds)

        val teamQuota = snapshot.quotas[3]
        assertEquals(100.0, teamQuota.percentRemaining)
        assertEquals("0/10000 team credits", teamQuota.resetText)
    }

    @Test
    fun `should measure an Enterprise member's requests against the plan's whole capacity when no limit is given`() {
        val json = """
        {
            "membershipType": "enterprise",
            "limitType": "team",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 0,
                    "limit": 0,
                    "remaining": 0,
                    "breakdown": {
                        "included": 0,
                        "bonus": 184,
                        "total": 184
                    },
                    "totalPercentUsed": 50.0
                },
                "onDemand": { "enabled": false, "used": 0, "limit": 0, "remaining": 0 }
            },
            "teamUsage": {
                "onDemand": { "enabled": false, "used": 0, "limit": 0, "remaining": 0 }
            }
        }
        """

        val snapshot = parse(json)

        assertEquals(1, snapshot.quotas.size)
        val quota = snapshot.quotas[0]
        assertEquals(QuotaType.TimeLimit("Monthly"), quota.quotaType)
        // 50% used -> 50% remaining
        assertTrue(abs(quota.percentRemaining - 50.0) < 0.5)
    }

    // Error Cases

    @Test
    fun `should fail when Cursor answers with nothing`() {
        val json = "{}"

        assertTrue(refreshAdded(json, "header.eyJzdWIiOiJmaXh0dXJlLXVzZXIifQ.signature") is RefreshOutcome.Failed)
    }

    @Test
    fun `should fail when Cursor answers with something that isn't JSON`() {
        val json = "not json"

        assertTrue(refreshAdded(json, "header.eyJzdWIiOiJmaXh0dXJlLXVzZXIifQ.signature") is RefreshOutcome.Failed)
    }

    @Test
    fun `should fail when Cursor reports no personal usage for a plan that isn't unlimited`() {
        val json = """
        {
            "membershipType": "pro",
            "isUnlimited": false
        }
        """

        assertTrue(refreshAdded(json, "header.eyJzdWIiOiJmaXh0dXJlLXVzZXIifQ.signature") is RefreshOutcome.Failed)
    }

    // Billing Cycle

    @Test
    fun `should know the reset when the billing cycle end has fractional seconds`() {
        val json = """
        {
            "membershipType": "pro",
            "isUnlimited": false,
            "billingCycleEnd": "2025-03-01T00:00:00.000Z",
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 100,
                    "limit": 500,
                    "remaining": 400
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """

        val snapshot = parse(json)
        assertNotNull(snapshot.quotas[0].resetsAtSeconds)
    }

    @Test
    fun `should know the reset when the billing cycle end has whole seconds`() {
        val json = """
        {
            "membershipType": "pro",
            "isUnlimited": false,
            "billingCycleEnd": "2025-03-01T00:00:00Z",
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 100,
                    "limit": 500,
                    "remaining": 400
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """

        val snapshot = parse(json)
        assertNotNull(snapshot.quotas[0].resetsAtSeconds)
    }

    // Auto / API pool percents

    @Test
    fun `should show one monthly window when Cursor reports only the total`() {
        val json = """
        {
            "membershipType": "pro",
            "billingCycleStart": "2026-01-01T00:00:00.000Z",
            "billingCycleEnd": "2026-02-01T00:00:00.000Z",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 100,
                    "limit": 500,
                    "remaining": 400,
                    "totalPercentUsed": 20
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """

        val snapshot = parse(json)

        assertEquals(1, snapshot.quotas.size)
        assertEquals(QuotaType.TimeLimit("Monthly"), snapshot.quotas[0].quotaType)
        assertEquals("time:Monthly", snapshot.quotas[0].quotaType.quotaKey)
        assertTrue(abs(snapshot.quotas[0].percentRemaining - 80) < 0.01)
        assertEquals("100/500 requests", snapshot.quotas[0].resetText)
    }

    @Test
    fun `should show the Auto and API pools full when nothing of them is used`() {
        val json = """
        {
            "membershipType": "pro",
            "billingCycleStart": "2026-01-01T00:00:00.000Z",
            "billingCycleEnd": "2026-01-31T00:00:00.000Z",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 0,
                    "limit": 500,
                    "remaining": 500,
                    "autoPercentUsed": 0,
                    "apiPercentUsed": 0,
                    "totalPercentUsed": 0
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """

        val snapshot = parse(json)

        assertEquals(3, snapshot.quotas.size)
        assertEquals(100.0, snapshot.quotas[0].percentRemaining)
        assertEquals(QuotaType.TimeLimit("Auto"), snapshot.quotas[1].quotaType)
        assertEquals(100.0, snapshot.quotas[1].percentRemaining)
        assertEquals(QuotaType.TimeLimit("API"), snapshot.quotas[2].quotaType)
        assertEquals(100.0, snapshot.quotas[2].percentRemaining)
        assertEquals(30.0 * 24 * 3600, snapshot.quotas[1].windowSeconds)
    }

    @Test
    fun `should show no Auto or API pool when Cursor leaves their share empty`() {
        val json = """
        {
            "membershipType": "pro",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 50,
                    "limit": 100,
                    "remaining": 50,
                    "autoPercentUsed": null,
                    "apiPercentUsed": null,
                    "totalPercentUsed": 50
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """

        val snapshot = parse(json)

        assertEquals(1, snapshot.quotas.size)
        assertEquals(QuotaType.TimeLimit("Monthly"), snapshot.quotas[0].quotaType)
        assertEquals(50.0, snapshot.quotas[0].percentRemaining)
    }

    @Test
    fun `should show no Auto or API pool when their share isn't a number`() {
        val json = """
        {
            "membershipType": "pro",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 50,
                    "limit": 100,
                    "remaining": 50,
                    "autoPercentUsed": "high",
                    "apiPercentUsed": [],
                    "totalPercentUsed": 50
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """

        val snapshot = parse(json)

        assertEquals(1, snapshot.quotas.size)
        assertEquals(QuotaType.TimeLimit("Monthly"), snapshot.quotas[0].quotaType)
    }

    @Test
    fun `should show no Auto or API pool when their share is true or false`() {
        // JSON true/false are CFBoolean and must not become 1.0 / 0.0. Integer 0
        // still has to produce a card (see `should show the Auto and API pools full when nothing of them is used`).
        val json = """
        {
            "membershipType": "pro",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 50,
                    "limit": 100,
                    "remaining": 50,
                    "autoPercentUsed": false,
                    "apiPercentUsed": true,
                    "totalPercentUsed": 50
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """

        val snapshot = parse(json)

        assertEquals(1, snapshot.quotas.size)
        assertEquals(QuotaType.TimeLimit("Monthly"), snapshot.quotas[0].quotaType)
        assertEquals(50.0, snapshot.quotas[0].percentRemaining)
    }

    @Test
    fun `should show nothing left, not below zero, when the Auto and API pools are over their limit`() {
        val json = """
        {
            "membershipType": "pro",
            "billingCycleStart": "2026-01-01T00:00:00.000Z",
            "billingCycleEnd": "2026-02-01T00:00:00.000Z",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 500,
                    "limit": 500,
                    "remaining": 0,
                    "autoPercentUsed": 142.5,
                    "apiPercentUsed": 100.1,
                    "totalPercentUsed": 110
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """

        val snapshot = parse(json)

        assertEquals(3, snapshot.quotas.size)
        assertEquals(0.0, snapshot.quotas[0].percentRemaining)
        assertEquals(QuotaType.TimeLimit("Auto"), snapshot.quotas[1].quotaType)
        assertEquals(0.0, snapshot.quotas[1].percentRemaining)
        assertEquals(QuotaType.TimeLimit("API"), snapshot.quotas[2].quotaType)
        assertEquals(0.0, snapshot.quotas[2].percentRemaining)
    }

    @Test
    fun `should show no Auto or API pool when their share is negative`() {
        val json = """
        {
            "membershipType": "pro",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 10,
                    "limit": 100,
                    "remaining": 90,
                    "autoPercentUsed": -4,
                    "apiPercentUsed": -0.1,
                    "totalPercentUsed": 10
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """

        val snapshot = parse(json)

        assertEquals(1, snapshot.quotas.size)
        assertEquals(QuotaType.TimeLimit("Monthly"), snapshot.quotas[0].quotaType)
        assertEquals(90.0, snapshot.quotas[0].percentRemaining)
    }

    @Test
    fun `should show the Auto and API pools without reset or pace when the billing cycle has no start`() {
        // Existing fixtures sometimes only have billingCycleEnd (see `should show a Pro plan's monthly requests used out of its limit`).
        val json = """
        {
            "membershipType": "pro",
            "billingCycleEnd": "2025-02-01T00:00:00Z",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 123,
                    "limit": 500,
                    "remaining": 377,
                    "autoPercentUsed": 10,
                    "apiPercentUsed": 20,
                    "totalPercentUsed": 15
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """

        val snapshot = parse(json)

        assertEquals(3, snapshot.quotas.size)

        val monthly = snapshot.quotas[0]
        assertEquals(QuotaType.TimeLimit("Monthly"), monthly.quotaType)
        assertTrue(abs(monthly.percentRemaining - 85) < 0.01)
        assertEquals("75/500 requests", monthly.resetText)
        assertNotNull(monthly.resetsAtSeconds)
        assertNull(monthly.windowSeconds)

        val auto = snapshot.quotas[1]
        assertEquals(QuotaType.TimeLimit("Auto"), auto.quotaType)
        assertEquals(90.0, auto.percentRemaining)
        assertNull(auto.resetText)
        assertNull(auto.resetsAtSeconds)
        assertNull(auto.windowSeconds)

        val api = snapshot.quotas[2]
        assertEquals(QuotaType.TimeLimit("API"), api.quotaType)
        assertEquals(80.0, api.percentRemaining)
        assertNull(api.resetsAtSeconds)
        assertNull(api.windowSeconds)
    }

    @Test
    fun `should show the Auto and API pools without reset or window when the billing cycle start is unreadable`() {
        val json = """
        {
            "membershipType": "pro",
            "billingCycleStart": "not-a-date",
            "billingCycleEnd": "2026-02-01T00:00:00.000Z",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 10,
                    "limit": 100,
                    "remaining": 90,
                    "autoPercentUsed": 5,
                    "apiPercentUsed": 8,
                    "totalPercentUsed": 6
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """

        val snapshot = parse(json)

        assertEquals(3, snapshot.quotas.size)
        assertNotNull(snapshot.quotas[0].resetsAtSeconds)
        assertNull(snapshot.quotas[1].resetsAtSeconds)
        assertNull(snapshot.quotas[1].windowSeconds)
        assertNull(snapshot.quotas[2].resetsAtSeconds)
        assertNull(snapshot.quotas[2].windowSeconds)
    }

    @Test
    fun `should keep the monthly window first so the menu bar shows it by default`() {
        val json = """
        {
            "membershipType": "ultra",
            "billingCycleStart": "2026-02-06T03:34:49.000Z",
            "billingCycleEnd": "2026-03-06T03:34:49.000Z",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 326,
                    "limit": 40000,
                    "remaining": 39674,
                    "autoPercentUsed": 39.9,
                    "apiPercentUsed": 97.2,
                    "totalPercentUsed": 44.7
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """

        val snapshot = parse(json)
        val first = required(snapshot.quotas.firstOrNull())

        assertEquals(QuotaType.TimeLimit("Monthly"), first.quotaType)
        assertEquals("time:Monthly", first.quotaType.quotaKey)
        assertTrue(snapshot.quotas.any { it.quotaType.quotaKey == "time:API" })
    }

    // JWT Parsing

    @Test
    fun `should sign in as the user the login token names`() {
        // JWT with payload: {"sub": "user_abc123", "iat": 1234567890}
        val header = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
        val payload = "eyJzdWIiOiJ1c2VyX2FiYzEyMyIsImlhdCI6MTIzNDU2Nzg5MH0"
        val signature = "SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        val jwt = "$header.$payload.$signature"

        val userId = userID(jwt)
        assertEquals("user_abc123", userId)
    }

    @Test
    fun `should sign in as a user whose id holds a pipe, as Cursor's do`() {
        // Cursor JWTs have sub like "github|user_01J6BBEPT2KSQKPPRGXDY8M1F4"
        // Payload: {"sub": "github|user_01ABC", "type": "session"}
        // base64url of {"sub":"github|user_01ABC","type":"session"} =
        val payloadJson = """{"sub":"github|user_01ABC","type":"session"}"""
        val payloadBase64 = Base64.getEncoder().encodeToString(payloadJson.toByteArray())
            .replace("+", "-")
            .replace("/", "_")
            .replace("=", "")
        val jwt = "eyJhbGciOiJIUzI1NiJ9.$payloadBase64.sig"

        val userId = userID(jwt)
        assertEquals("github|user_01ABC", userId)
    }

    @Test
    fun `should sign in as the user a short login token names`() {
        // Payload: {"sub": "u1"}
        val header = "eyJhbGciOiJIUzI1NiJ9"
        val payload = "eyJzdWIiOiJ1MSJ9"
        val jwt = "$header.$payload.sig"

        val userId = userID(jwt)
        assertEquals("u1", userId)
    }

    @ParameterizedTest
    @ValueSource(strings = ["not-a-jwt", "eyJhbGciOiJIUzI1NiJ9.eyJpYXQiOjEyM30.sig"])
    fun `should sign in without a session cookie when the login token names no user`(token: String) {
        // Not a JWT, or one with no `sub`: the cookie is left out, and Cursor answers for itself.
        val capture = CookieCapture()
        refreshAdded("""{"isUnlimited":true}""", token, capture)
        assertNull(capture.cookie)
    }

    // Numeric Type Handling

    @Test
    fun `should show the requests left when Cursor counts them with decimals`() {
        // Some API responses return numbers as doubles
        val json = """
        {
            "membershipType": "pro",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 123.0,
                    "limit": 500.0,
                    "remaining": 377.0
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """

        val snapshot = parse(json)

        assertEquals(1, snapshot.quotas.size)
        assertTrue(abs(snapshot.quotas[0].percentRemaining - 75.4) < 0.1)
    }

    // Account Tier Detection

    @Test
    fun `should show the Ultra plan`() {
        val json = """
        {
            "membershipType": "ultra",
            "isUnlimited": false,
            "individualUsage": {
                "plan": { "enabled": true, "used": 1, "limit": 40000, "remaining": 39999 },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """

        val snapshot = parse(json)
        assertEquals(AccountTier.Custom("ULTRA"), snapshot.accountTier)
    }
}

internal class CursorAccountTest {
    private val stubs = mutableListOf<StubbedProvider>()

    @AfterEach
    fun cleanUp() = stubs.forEach { it.cleanUp() }

    private fun token(subject: String): String {
        val data = """{"sub":"$subject"}""".toByteArray()
        return "header." + Base64.getEncoder().encodeToString(data).replace("+", "-").replace("/", "_").replace("=", "") + ".signature"
    }

    /** The Cursor app's database, holding [token] as its login — a file only this test's fake reads. */
    private fun database(root: File, token: String?): File {
        val file = File(root, "Library/Application Support/Cursor/User/globalStorage/state.vscdb")
        file.parentFile.mkdirs()
        file.writeText(token?.let { "cursorAuth/accessToken=$it" } ?: "")
        return file
    }

    /** SQLite as this test's database file answers it: the login's token, when it holds one. */
    private val cursorDatabase = FakeDatabase { contents, _ ->
        val token = contents.substringAfter("cursorAuth/accessToken=", "").takeIf { it.isNotEmpty() }
        listOfNotNull(token?.let { mapOf("token" to StoredValue.Text(it)) })
    }

    /** Cursor's provider over its own connections: [home] as `~`, [network] answering. */
    private fun make(
        home: String, network: StubNetwork, settings: InMemoryProviderSettings = InMemoryProviderSettings(),
        vault: MemoryVault? = MemoryVault(), environment: (String) -> String? = { null },
    ): Provider {
        val definition = TestDefinitions.builtIn("cursor")
        // Fakes for every connection, with every environment variable answering as [environment] does.
        val connections = DataSources(
            home = home, environment = environment, network = network, loopback = network,
            makeCLIExecutor = { FakeCLIExecutor() }, makeCommandExecutor = { FakeCLIExecutor() },
            transports = RPCTransportFactory { _, _, _, _ -> AnsweringTransport() }, directory = { DEDICATED_FOLDER },
            processEnvironment = { emptyMap() }, files = DiskFiles, processPaths = { emptyList() },
            security = FakeSecurity { SecurityResult(44, "") }, database = cursorDatabase,
            browserCookies = FakeCookies(), browserStorage = FakeStorage(), loginShell = null,
            cloudWatch = null, priceCatalog = null, scriptEngine = GraalScriptEngine(), now = { System.currentTimeMillis() / 1000.0 },
        )
        return Provider(
            definition = definition,
            settings = settings,
            saved = settings.accounts("cursor"),
            makeDataSource = { source, login -> connections.make(source, "cursor", vault?.scoped(login), TestDefinitions.builtIns::script) },
            folders = InMemoryLoginFolders(),
            vault = vault,
            paths = HomePaths(home, environment),
            isExecutable = { true },
            locate = { it },
        )
    }

    @Test
    fun `should keep the Cursor app's login and added logins apart through rename, relaunch, a lost token and removal`() {
        val root = Files.createTempDirectory("cursor-accounts").toRealPath().toFile()
        try {
            val personal = token("personal|desktop")
            val work = token("work|account")
            val other = token("work|similar")
            val db = database(root, personal)
            val bytes = db.readBytes()
            val settings = InMemoryProviderSettings()
            val vault = MemoryVault()
            val problems = mutableListOf<String>()
            val network = StubNetwork { call ->
                val cookie = call.headers.entries.firstOrNull { it.key.equals("Cookie", true) }?.value ?: ""
                val remaining = when {
                    cookie.contains("personal|desktop::") -> 80
                    cookie.contains("work|account::") -> 40
                    cookie.contains("work|similar::") -> 20
                    else -> -1
                }
                if (remaining < 0) problems += "cookie $cookie"
                Response(200, body = "{\"individualUsage\":{\"plan\":{\"enabled\":true,\"limit\":100,\"used\":${100 - remaining}}}}".encodeToByteArray())
            }
            val make = { make(root.path, network, settings, vault, environment = { personal }) }
            val first = make()
            assertEquals("Cursor", first.defaultAccount.displayName)
            val added = first.accounts.add(filling = mapOf("accessToken" to work)).done()
            val second = first.accounts.add(filling = mapOf("accessToken" to other)).done()
            first.accounts.rename(added, "Work")
            first.accounts.rename(second, "Other work")
            assertTrue(added.displayName == "Work" && second.displayName == "Other work")
            assertEquals(80.0, first.refreshPlain().usage().quotas[0].percentRemaining)
            assertEquals(40.0, first.refreshNow(added).usage().quotas[0].percentRemaining)
            assertEquals(20.0, first.refreshNow(second).usage().quotas[0].percentRemaining)
            assertTrue(settings.accounts("cursor").all { it.probeConfig.isEmpty() })
            val relaunched = make()
            val saved = required(relaunched.accounts.firstOrNull { it.id == added.id })
            assertEquals("Work", saved.displayName)
            assertEquals(40.0, relaunched.refreshNow(saved).usage().quotas[0].percentRemaining)
            vault.delete("accessToken", saved.id)
            assertEquals(RefreshOutcome.Failed(UsageError.AuthenticationRequired), relaunched.refreshNow(saved))
            assertEquals(80.0, relaunched.refreshPlain().usage().quotas[0].percentRemaining)
            relaunched.accounts.remove(saved)
            assertFalse(settings.accounts("cursor").any { it.accountId == saved.accountId })
            assertEquals(2, relaunched.accounts.size)
            assertArrayEquals(bytes, db.readBytes())
            assertEquals(emptyList<String>(), problems)
        } finally {
            root.deleteRecursively()
        }
    }

    @ParameterizedTest
    @MethodSource("refusals")
    fun `should tell the person how to recover when Cursor refuses or errors`(status: Int, error: UsageError) {
        val network = StubNetwork { Response(status, body = "{}".encodeToByteArray()) }
        val stub = StubbedProvider(network = network).also { stubs += it }
        val vault = MemoryVault()
        val provider = stub.make(TestDefinitions.builtIn("cursor"), vault = vault, settings = InMemoryProviderSettings())
        val account = provider.accounts.add(filling = mapOf("accessToken" to token("test"))).done()
        val outcome = provider.refreshNow(account)
        assertEquals(RefreshOutcome.Failed(error), outcome)
    }

    @Test
    fun `should say it is rate limited, not an HTTP error, when Cursor answers 429`() {
        val network = StubNetwork { Response(429, body = "{}".encodeToByteArray()) }
        val stub = StubbedProvider(network = network).also { stubs += it }
        val provider = stub.make(TestDefinitions.builtIn("cursor"), vault = MemoryVault(), settings = InMemoryProviderSettings())
        val account = provider.accounts.add(filling = mapOf("accessToken" to token("test"))).done()
        assertEquals("rateLimited", (provider.refreshNow(account) as? RefreshOutcome.Failed)?.error?.tag)
    }

    @Test
    fun `should ask to sign in again in Cursor's settings when the Cursor app has no login on this Mac`() {
        val stub = StubbedProvider().also { stubs += it }
        val provider = stub.make(TestDefinitions.builtIn("cursor"), settings = InMemoryProviderSettings())
        assertFalse(provider.isPlainAvailable())
        assertEquals(RefreshOutcome.Failed(UsageError.AuthenticationRequired), provider.refreshPlain())
        assertEquals("Sign in again in Cursor settings, then refresh.", provider.configuration.keyHint)
    }

    companion object {
        @JvmStatic
        fun refusals(): List<Arguments> = listOf(
            Arguments.of(401, UsageError.SessionExpired("Re-authenticate in Cursor settings.")),
            Arguments.of(403, UsageError.AuthenticationRequired),
            Arguments.of(201, UsageError.ExecutionFailed("HTTP error: 201")),
            Arguments.of(500, UsageError.ExecutionFailed("HTTP error: 500")),
        )
    }
}
