package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.mapping.iso8601Seconds
import com.tddworks.claudebar.quotas.AccountTier
import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageError
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Kimi API usage. */
class KimiAPIDefinitionParsingTest {
    private fun usage(limit: String, used: String? = "100", remaining: String? = null, reset: String = "2025-06-09T00:00:00Z", scope: String = "FEATURE_CODING"): String {
        val fields = listOfNotNull(
            "\"limit\": \"$limit\"",
            used?.let { "\"used\": \"$it\"" },
            remaining?.let { "\"remaining\": \"$it\"" },
            "\"resetTime\": \"$reset\"",
        ).joinToString(", ")
        return """{ "usages": [{ "scope": "$scope", "detail": { $fields } }] }"""
    }

    // Full response

    @Test
    fun `should show the weekly quota and the 5-hour session when Kimi reports both`() {
        val json = """
        {
            "usages": [{
                "scope": "FEATURE_CODING",
                "detail": {
                    "limit": "2048",
                    "used": "214",
                    "remaining": "1834",
                    "resetTime": "2025-06-09T00:00:00.000Z"
                },
                "limits": [{
                    "window": { "duration": 300, "timeUnit": "TIME_UNIT_MINUTE" },
                    "detail": {
                        "limit": "200",
                        "used": "139",
                        "remaining": "61",
                        "resetTime": "2025-06-03T15:30:00.000Z"
                    }
                }]
            }]
        }
        """

        val snapshot = KimiDefinitionFixtures.api(json, "kimi")

        assertEquals("kimi", snapshot.providerId)
        assertEquals(2, snapshot.quotas.size)

        val weekly = assertNotNull(snapshot.quota(QuotaType.Weekly))
        assertTrue(weekly.percentRemaining > 89.5)
        assertTrue(weekly.percentRemaining < 89.6)
        assertEquals("214/2048 requests", weekly.resetText)
        assertNotNull(weekly.resetsAtSeconds)

        val session = assertNotNull(snapshot.quota(QuotaType.Session))
        assertEquals(30.5, session.percentRemaining)
        assertEquals("139/200 requests (5h)", session.resetText)
        assertNotNull(session.resetsAtSeconds)
    }

    @Test
    fun `should show the Moderato plan when the weekly limit is 2048 requests`() {
        val snapshot = KimiDefinitionFixtures.api(usage("2048", "100", "1948"), "kimi")

        assertEquals(AccountTier.Custom("Moderato"), snapshot.accountTier)
    }

    @Test
    fun `should show the Andante plan when the weekly limit is 1024 requests`() {
        val snapshot = KimiDefinitionFixtures.api(usage("1024", "50", "974"), "kimi")

        assertEquals(AccountTier.Custom("Andante"), snapshot.accountTier)
    }

    @Test
    fun `should show the Allegretto plan when the weekly limit is 7168 requests`() {
        val snapshot = KimiDefinitionFixtures.api(usage("7168", "500", "6668"), "kimi")

        assertEquals(AccountTier.Custom("Allegretto"), snapshot.accountTier)
    }

    @Test
    fun `should show no plan when the weekly limit matches no known plan`() {
        val snapshot = KimiDefinitionFixtures.api(usage("500", "50", "450"), "kimi")

        assertNull(snapshot.accountTier)
    }

    // Missing limits array

    @Test
    fun `should show only the weekly quota when Kimi reports no rate-limit windows`() {
        val snapshot = KimiDefinitionFixtures.api(usage("2048", "214", "1834"), "kimi")

        assertEquals(1, snapshot.quotas.size)
        assertNotNull(snapshot.quota(QuotaType.Weekly))
        assertNull(snapshot.quota(QuotaType.Session))
    }

    // Missing used / remaining

    @Test
    fun `should work out the plan's requests used from its limit and what remains when Kimi omits the used count`() {
        val snapshot = KimiDefinitionFixtures.api(usage("1000", used = null, remaining = "750"), "kimi")

        // Not one of the weekly plans: "Plan", with no guessed window.
        val plan = assertNotNull(snapshot.quota(QuotaType.TimeLimit("Plan")))
        assertEquals(75.0, plan.percentRemaining)
        assertEquals("250/1000 requests", plan.resetText)
    }

    @Test
    fun `should work out what remains of the plan from its limit and requests used when Kimi omits the remaining count`() {
        val snapshot = KimiDefinitionFixtures.api(usage("1000", used = "300", remaining = null), "kimi")

        val plan = assertNotNull(snapshot.quota(QuotaType.TimeLimit("Plan")))
        assertEquals(70.0, plan.percentRemaining)
        assertEquals("300/1000 requests", plan.resetText)
    }

    @Test
    fun `should show no quota when Kimi reports neither requests used nor remaining`() {
        val snapshot = KimiDefinitionFixtures.api(usage("2048", used = null, remaining = null), "kimi")

        // Nothing reported is no quota, never a made-up 100% (the Left law).
        assertNull(snapshot.quota(QuotaType.Weekly))
    }

    // Reset time

    @Test
    fun `should show the exact reset time when Kimi gives it with fractional seconds`() {
        val snapshot = KimiDefinitionFixtures.api(usage("1000", "100", "900", reset = "2025-06-09T12:30:45.123Z"), "kimi")

        val plan = assertNotNull(snapshot.quota(QuotaType.TimeLimit("Plan")))
        val resetsAt = assertNotNull(plan.resetsAtSeconds)
        assertEquals(assertNotNull(iso8601Seconds("2025-06-09T12:30:45.123Z")), resetsAt, 0.0005)
    }

    @Test
    fun `should show a reset time when Kimi gives it without fractional seconds`() {
        val snapshot = KimiDefinitionFixtures.api(usage("1000", "100", "900", reset = "2025-06-09T12:30:45Z"), "kimi")

        assertNotNull(snapshot.quota(QuotaType.TimeLimit("Plan"))?.resetsAtSeconds)
    }

    // Errors

    @Test
    fun `should fail to read usage when Kimi answers with something that is not JSON`() {
        assertFailsWith<UsageError> { KimiDefinitionFixtures.api("not json", "kimi") }
    }

    @Test
    fun `should fail to read usage when Kimi reports no coding usage`() {
        assertFailsWith<UsageError> { KimiDefinitionFixtures.api(usage("1000", "100", "900", scope = "FEATURE_CHAT"), "kimi") }
    }

    @Test
    fun `should fail to read usage when Kimi reports no usage at all`() {
        assertFailsWith<UsageError> { KimiDefinitionFixtures.api("""{ "usages": [] }""", "kimi") }
    }

    // Edge cases

    @Test
    fun `should show no quota when the limit is zero`() {
        val snapshot = KimiDefinitionFixtures.api(usage("0", "0", "0"), "kimi")

        // A limit of 0 is nothing to show, never a made-up 100% (the Left law).
        assertTrue(snapshot.quotas.isEmpty())
    }

    @Test
    fun `should show the 5-hour window as the session when Kimi reports several rate-limit windows`() {
        val json = """
        {
            "usages": [{
                "scope": "FEATURE_CODING",
                "detail": { "limit": "2048", "used": "100", "remaining": "1948", "resetTime": "2025-06-09T00:00:00Z" },
                "limits": [
                    {
                        "window": { "duration": 60, "timeUnit": "TIME_UNIT_MINUTE" },
                        "detail": { "limit": "50", "used": "10", "remaining": "40", "resetTime": "2025-06-03T15:00:00Z" }
                    },
                    {
                        "window": { "duration": 300, "timeUnit": "TIME_UNIT_MINUTE" },
                        "detail": { "limit": "200", "used": "80", "remaining": "120", "resetTime": "2025-06-03T15:30:00Z" }
                    }
                ]
            }]
        }
        """

        val session = assertNotNull(KimiDefinitionFixtures.api(json, "kimi").quota(QuotaType.Session))
        assertEquals(60.0, session.percentRemaining)
        assertEquals("80/200 requests (5h)", session.resetText)
    }
}
