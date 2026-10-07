package com.tddworks.claudebar.providers

import com.tddworks.claudebar.quotas.AccountTier
import com.tddworks.claudebar.quotas.CostUsage
import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageError
import com.tddworks.claudebar.quotas.UsageSnapshot
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.double
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File
import java.io.IOException
import java.math.BigDecimal
import java.time.Instant
import java.util.concurrent.atomic.AtomicInteger

/** Dollars as nano-units: "5.41" → 5_410_000_000. */
private fun dollars(amount: String): Long = BigDecimal(amount).movePointRight(9).longValueExact()

/**
 * `claude.json`'s `api` data source — the key lookup, the OAuth refresh, the usage request and
 * its JSON mapping — over stubbed connections. Ported from `ClaudeAPITests.swift`.
 */
class ClaudeAPITest {

    // Helpers

    /** A usage body read with a valid credentials file whose plan is [subscriptionType]. */
    private fun usage(json: String, subscriptionType: String? = "claude_pro"): UsageSnapshot {
        val claude = ClaudeHarness()
        try {
            return claude.readAPIResponse(json, subscriptionType)
        } finally {
            claude.cleanUp()
        }
    }

    private fun claude(test: (ClaudeHarness) -> Unit) {
        val claude = ClaudeHarness()
        try {
            test(claude)
        } finally {
            claude.cleanUp()
        }
    }

    // Availability

    @Test
    fun `should be available when Claude's credentials file exists`() = claude { claude ->
        claude.writeCredentials()

        val source = claude.dataSource("api")

        assertTrue(source.hasKey)
        assertTrue(source.isReady())
    }

    @Test
    fun `should be unavailable when there are no credentials`() = claude { claude ->
        val source = claude.dataSource("api")

        assertFalse(source.hasKey)
        assertFalse(source.isReady())
    }

    // Snapshot cache (TTL)

    @Test
    fun `should show the remembered usage without asking Claude again within the cache time`() = claude { claude ->
        claude.writeCredentials(subscriptionType = "claude_max")
        val first = """{ "five_hour": { "utilization": 25.0, "resets_at": "2025-01-15T10:00:00Z" } }"""
        // Any request after the first would read 50% used.
        val later = """{ "five_hour": { "utilization": 50.0 } }"""
        val calls = AtomicInteger()
        claude.answer { claudeResponse(200, body = if (calls.incrementAndGet() == 1) first else later) }
        val source = claude.dataSource("api")

        val one = claude.fetchUsage(source)
        val two = claude.fetchUsage(source)
        val three = claude.fetchUsage(source)

        assertEquals(75.0, one.quotas.first().percentRemaining)
        assertEquals(75.0, two.quotas.first().percentRemaining)
        assertEquals(75.0, three.quotas.first().percentRemaining)
    }

    // Rate limit (HTTP 429)

    @Test
    fun `should wait until the time Claude names when it rate-limits the request`() = claude { claude ->
        claude.writeCredentials()
        claude.answer { claudeResponse(429, mapOf("Retry-After" to "120")) }

        val error = claude.failure(claude.dataSource("api"))

        assertEquals(UsageError.RateLimited(claude.now + 120), error)
    }

    @Test
    fun `should wait five minutes when Claude rate-limits without saying how long`() = claude { claude ->
        claude.writeCredentials()
        claude.answer { claudeResponse(429) }

        val error = claude.failure(claude.dataSource("api"))

        assertEquals(UsageError.RateLimited(claude.now + 300), error)
    }

    @Test
    fun `should not ask Claude again while a rate limit lasts`() = claude { claude ->
        claude.writeCredentials()
        // The first request is throttled; any later one would succeed.
        val calls = AtomicInteger()
        claude.answer {
            if (calls.incrementAndGet() == 1) claudeResponse(429, mapOf("Retry-After" to "600"))
            else claudeResponse(200, body = """{ "five_hour": { "utilization": 10.0 } }""")
        }
        val source = claude.dataSource("api")

        claude.failure(source)
        val second = claude.failure(source)

        assertEquals(UsageError.RateLimited(claude.now + 600), second)
    }

    // Authentication

    @Test
    fun `should ask to sign in when there are no credentials`() = claude { claude ->
        val error = claude.failure(claude.dataSource("api"))

        assertEquals(UsageError.AuthenticationRequired, error)
    }

    // Response parsing

    @Test
    fun `should show the five-hour window as the session with 74_5% left on a Max plan`() {
        val snapshot = usage(
            """{ "five_hour": { "utilization": 25.5, "resets_at": "2025-01-15T10:00:00Z" } }""",
            subscriptionType = "claude_max",
        )

        assertEquals("claude", snapshot.providerId)
        assertEquals(AccountTier.ClaudeMax, snapshot.accountTier)
        val session = snapshot.quotas.firstOrNull { it.quotaType == QuotaType.Session }
        assertEquals(74.5, session?.percentRemaining) // 100 - 25.5
        assertNotNull(session?.resetsAtSeconds)
    }

    @Test
    fun `should write the reset countdown in hours, never days, and none for a window already past`() = claude { claude ->
        claude.now = 1_750_000_000.0
        val resetsAt = Instant.ofEpochSecond((claude.now + 50 * 3600 + 3 * 60).toLong()).toString()
        val past = Instant.ofEpochSecond((claude.now - 60).toLong()).toString()

        val snapshot = claude.readAPIResponse(
            """
            {
              "five_hour": { "utilization": 10, "resets_at": "$past" },
              "seven_day": { "utilization": 10, "resets_at": "$resetsAt" }
            }
            """,
        )

        assertEquals("Resets in 50h 3m", snapshot.quota(QuotaType.Weekly)?.resetText)
        assertNull(snapshot.quota(QuotaType.Session)?.resetText)
    }

    @Test
    fun `should show the seven-day window as weekly with 55% left`() {
        val snapshot = usage(
            """
            {
              "five_hour": { "utilization": 10.0, "resets_at": "2025-01-15T10:00:00Z" },
              "seven_day": { "utilization": 45.0, "resets_at": "2025-01-20T00:00:00Z" }
            }
            """,
            subscriptionType = null,
        )

        assertEquals(55.0, snapshot.quotas.firstOrNull { it.quotaType == QuotaType.Weekly }?.percentRemaining) // 100 - 45
    }

    @Test
    fun `should show Sonnet and Opus quotas with what is left of each`() {
        val snapshot = usage(
            """
            {
              "five_hour": { "utilization": 10.0, "resets_at": "2025-01-15T10:00:00Z" },
              "seven_day_sonnet": { "utilization": 30.0, "resets_at": "2025-01-20T00:00:00Z" },
              "seven_day_opus": { "utilization": 60.0, "resets_at": "2025-01-20T00:00:00Z" }
            }
            """,
            subscriptionType = null,
        )

        assertEquals(70.0, snapshot.quota(QuotaType.ModelSpecific("sonnet"))?.percentRemaining) // 100 - 30
        assertEquals(40.0, snapshot.quota(QuotaType.ModelSpecific("opus"))?.percentRemaining) // 100 - 60
    }

    @Test
    fun `should show a Fable quota when Claude reports it as a model limit, without duplicating session or weekly`() {
        // Newer API responses report model limits via a generic "limits" array
        // (kind "weekly_scoped" + scope.model.display_name) instead of dedicated seven_day_<model> fields.
        val snapshot = usage(
            """
            {
              "five_hour": { "utilization": 23.0, "resets_at": "2026-07-02T07:09:59Z" },
              "seven_day": { "utilization": 10.0, "resets_at": "2026-07-02T10:59:59Z" },
              "seven_day_opus": null,
              "seven_day_sonnet": null,
              "limits": [
                { "kind": "session", "group": "session", "percent": 23, "resets_at": "2026-07-02T07:09:59Z", "scope": null },
                { "kind": "weekly_all", "group": "weekly", "percent": 10, "resets_at": "2026-07-02T10:59:59Z", "scope": null },
                { "kind": "weekly_scoped", "group": "weekly", "percent": 17, "resets_at": "2026-07-02T11:00:00Z",
                  "scope": { "model": { "id": null, "display_name": "Fable" }, "surface": null } }
              ]
            }
            """,
            subscriptionType = null,
        )

        val fable = snapshot.quota(QuotaType.ModelSpecific("fable"))
        assertEquals(83.0, fable?.percentRemaining) // 100 - 17
        assertNotNull(fable?.resetsAtSeconds)
        // Unscoped session/weekly entries in the limits array must not create duplicates
        assertEquals(1, snapshot.quotas.count { it.quotaType == QuotaType.Session })
        assertEquals(1, snapshot.quotas.count { it.quotaType == QuotaType.Weekly })
    }

    @Test
    fun `should skip malformed model limits, keep one per model, and show an over-quota model as negative`() {
        // Malformed scoped entries (no scope, no model, empty name, no percent) are skipped;
        // duplicate scoped entries yield one quota; a multi-word display name keys on its first
        // word; 105% used stays negative (over-quota signal).
        val snapshot = usage(
            """
            {
              "five_hour": { "utilization": 10.0, "resets_at": "2025-01-15T10:00:00Z" },
              "limits": [
                { "kind": "weekly_scoped", "group": "weekly", "percent": 50, "resets_at": "2025-01-20T00:00:00Z", "scope": null },
                { "kind": "weekly_scoped", "group": "weekly", "percent": 50, "resets_at": "2025-01-20T00:00:00Z", "scope": { "model": null } },
                { "kind": "weekly_scoped", "group": "weekly", "percent": 50, "resets_at": "2025-01-20T00:00:00Z",
                  "scope": { "model": { "id": null, "display_name": "" } } },
                { "kind": "weekly_scoped", "group": "weekly", "resets_at": "2025-01-20T00:00:00Z",
                  "scope": { "model": { "id": null, "display_name": "Opus" } } },
                { "kind": "weekly_scoped", "group": "weekly", "percent": 105, "resets_at": "2025-01-20T00:00:00Z",
                  "scope": { "model": { "id": null, "display_name": "Fable 5" } } },
                { "kind": "weekly_scoped", "group": "weekly", "percent": 40, "resets_at": "2025-01-20T00:00:00Z",
                  "scope": { "model": { "id": null, "display_name": "Fable" } } }
              ]
            }
            """,
            subscriptionType = null,
        )

        val fable = snapshot.quotas.filter { it.quotaType == QuotaType.ModelSpecific("fable") }
        assertEquals(1, fable.size)
        assertEquals(-5.0, fable.first().percentRemaining) // 100 - 105, first entry wins
        // Malformed entries produce no quotas: session (legacy) + fable only
        assertEquals(2, snapshot.quotas.size)
    }

    @Test
    fun `should show a model once when Claude reports it both ways`() {
        val snapshot = usage(
            """
            {
              "five_hour": { "utilization": 10.0, "resets_at": "2025-01-15T10:00:00Z" },
              "seven_day_opus": { "utilization": 60.0, "resets_at": "2025-01-20T00:00:00Z" },
              "limits": [
                { "kind": "weekly_scoped", "group": "weekly", "percent": 60, "resets_at": "2025-01-20T00:00:00Z",
                  "scope": { "model": { "id": null, "display_name": "Opus" }, "surface": null } }
              ]
            }
            """,
            subscriptionType = null,
        )

        val opus = snapshot.quotas.filter { it.quotaType == QuotaType.ModelSpecific("opus") }
        assertEquals(1, opus.size)
        assertEquals(40.0, opus.first().percentRemaining) // 100 - 60
    }

    // Money

    @Test
    fun `should show extra usage credits in dollars, not cents`() {
        // API returns used_credits and monthly_limit in cents
        val snapshot = usage(
            """
            {
              "five_hour": { "utilization": 10.0, "resets_at": "2025-01-15T10:00:00Z" },
              "extra_usage": { "is_enabled": true, "used_credits": 541, "monthly_limit": 2000 }
            }
            """,
            subscriptionType = "claude_pro",
        )

        assertEquals(AccountTier.ClaudePro, snapshot.accountTier)
        assertEquals(dollars("5.41"), snapshot.costUsage?.totalCostNanos) // 541 cents
        assertEquals(dollars("20"), snapshot.costUsage?.budgetNanos) // 2000 cents
        assertEquals(CostUsage.Kind.EXTRA_USAGE, snapshot.costUsage?.kind)
    }

    @Test
    fun `should show $26_72 of $50 extra usage, not $2672 of $5000`() {
        // Simulates the real scenario: $26.72 spent of $50 budget; API returns 2672 cents and 5000 cents
        val snapshot = usage(
            """
            {
              "five_hour": { "utilization": 10.0, "resets_at": "2025-01-15T10:00:00Z" },
              "extra_usage": { "is_enabled": true, "used_credits": 2672, "monthly_limit": 5000 }
            }
            """,
            subscriptionType = "claude_pro",
        )

        // 2672 cents -> $26.72 (NOT $2672.00)
        assertEquals(dollars("26.72"), snapshot.costUsage?.totalCostNanos)
        // 5000 cents -> $50.00 (NOT $5000.00)
        assertEquals(dollars("50"), snapshot.costUsage?.budgetNanos)
        assertEquals(CostUsage.Kind.EXTRA_USAGE, snapshot.costUsage?.kind)
    }

    @Test
    fun `should show the spend when it agrees with the older extra usage`() {
        val snapshot = usage(
            """
            {
              "spend": {
                "enabled": true,
                "used": { "amount_minor": 0, "currency": "USD", "exponent": 2 },
                "limit": { "amount_minor": 50000, "currency": "USD", "exponent": 2 }
              },
              "extra_usage": { "is_enabled": true, "used_credits": 0, "monthly_limit": 50000, "decimal_places": 2 }
            }
            """,
        )

        assertEquals(0L, snapshot.costUsage?.totalCostNanos)
        assertEquals(dollars("500"), snapshot.costUsage?.budgetNanos)
        assertEquals(CostUsage.Kind.EXTRA_USAGE, snapshot.costUsage?.kind)
    }

    @Test
    fun `should prefer the spend when the older extra usage differs`() {
        val snapshot = usage(
            """
            {
              "spend": {
                "enabled": true,
                "used": { "amount_minor": 125, "currency": "USD", "exponent": 2 },
                "limit": { "amount_minor": 1000, "currency": "USD", "exponent": 2 }
              },
              "extra_usage": { "is_enabled": true, "used_credits": 541, "monthly_limit": 2000, "decimal_places": 2 }
            }
            """,
        )

        assertEquals(dollars("1.25"), snapshot.costUsage?.totalCostNanos)
        assertEquals(dollars("10"), snapshot.costUsage?.budgetNanos)
    }

    @Test
    fun `should fall back to the older extra usage when the spend is negative`() {
        val snapshot = usage(
            """
            {
              "spend": {
                "enabled": true,
                "used": { "amount_minor": -125, "currency": "USD", "exponent": 2 },
                "limit": { "amount_minor": 1000, "currency": "USD", "exponent": 2 }
              },
              "extra_usage": { "is_enabled": true, "used_credits": 541, "monthly_limit": 2000, "decimal_places": 2 }
            }
            """,
        )

        // A negative amount_minor is invalid; the spend row is dropped instead of silently
        // flipping to +$1.25, and legacy takes over.
        assertEquals(dollars("5.41"), snapshot.costUsage?.totalCostNanos)
        assertEquals(dollars("20"), snapshot.costUsage?.budgetNanos)
        assertEquals(CostUsage.Kind.EXTRA_USAGE, snapshot.costUsage?.kind)
    }

    @Test
    fun `should show no extra usage rather than flip the sign of negative credits`() {
        val snapshot = usage(
            """
            {
              "five_hour": { "utilization": 10.0, "resets_at": "2025-01-15T10:00:00Z" },
              "extra_usage": { "is_enabled": true, "used_credits": -541, "monthly_limit": 2000, "decimal_places": 2 }
            }
            """,
        )

        assertNull(snapshot.costUsage)
    }

    @Test
    fun `should show no spend rather than an uncapped one when its cap is invalid`() {
        val snapshot = usage(
            """
            {
              "spend": {
                "enabled": true,
                "used":  { "amount_minor": 541, "currency": "USD", "exponent": 2 },
                "limit": { "amount_minor": -2000, "currency": "USD", "exponent": 2 }
              }
            }
            """,
        )

        // A present-but-invalid cap must not be reclassified as "no monthly cap"; the whole shape is dropped.
        assertNull(snapshot.costUsage)
    }

    @Test
    fun `should fall back to the older extra usage when the spend cap is invalid`() {
        val snapshot = usage(
            """
            {
              "spend": {
                "enabled": true,
                "used":  { "amount_minor": 125, "currency": "USD", "exponent": 2 },
                "limit": { "amount_minor": 2000, "currency": "USD", "exponent": -1 }
              },
              "extra_usage": { "is_enabled": true, "used_credits": 541, "monthly_limit": 2000, "decimal_places": 2 }
            }
            """,
        )

        assertEquals(dollars("5.41"), snapshot.costUsage?.totalCostNanos)
        assertEquals(dollars("20"), snapshot.costUsage?.budgetNanos)
    }

    @Test
    fun `should show no extra usage when its monthly limit is invalid`() {
        val snapshot = usage(
            """
            { "extra_usage": { "is_enabled": true, "used_credits": 541, "monthly_limit": -2000, "decimal_places": 2 } }
            """,
        )

        assertNull(snapshot.costUsage)
    }

    @Test
    fun `should show uncapped spend exactly, with no budget`() {
        val snapshot = usage(
            """
            {
              "spend": {
                "enabled": true,
                "used": { "amount_minor": 123456, "currency": "USD", "exponent": 2 },
                "limit": null,
                "percent": 0
              },
              "extra_usage": {
                "is_enabled": true,
                "monthly_limit": null,
                "used_credits": 123456,
                "decimal_places": 2,
                "currency": "USD"
              }
            }
            """,
        )

        assertEquals(dollars("1234.56"), snapshot.costUsage?.totalCostNanos)
        assertNull(snapshot.costUsage?.budgetNanos)
        assertEquals(CostUsage.Kind.EXTRA_USAGE, snapshot.costUsage?.kind)
    }

    @Test
    fun `should show spend in the precision Claude states for each amount`() {
        val snapshot = usage(
            """
            {
              "spend": {
                "enabled": true,
                "used": { "amount_minor": 12345, "exponent": 3 },
                "limit": { "amount_minor": 2000, "exponent": 1 }
              }
            }
            """,
        )

        assertEquals(dollars("12.345"), snapshot.costUsage?.totalCostNanos)
        assertEquals(dollars("200"), snapshot.costUsage?.budgetNanos)
    }

    @Test
    fun `should fall back to the older extra usage when the spend has no amount used`() {
        val snapshot = usage(
            """
            {
              "spend": { "enabled": true, "used": null, "limit": { "amount_minor": 1000, "exponent": 2 } },
              "extra_usage": { "is_enabled": true, "used_credits": 541, "monthly_limit": 2000 }
            }
            """,
        )

        assertEquals(dollars("5.41"), snapshot.costUsage?.totalCostNanos)
        assertEquals(dollars("20"), snapshot.costUsage?.budgetNanos)
        assertEquals(CostUsage.Kind.EXTRA_USAGE, snapshot.costUsage?.kind)
    }

    @Test
    fun `should show the older extra usage in the precision Claude states`() {
        val snapshot = usage(
            """
            { "extra_usage": { "is_enabled": true, "used_credits": 541, "monthly_limit": 2000, "decimal_places": 3 } }
            """,
        )

        assertEquals(dollars("0.541"), snapshot.costUsage?.totalCostNanos)
        assertEquals(dollars("2"), snapshot.costUsage?.budgetNanos)
        assertEquals(CostUsage.Kind.EXTRA_USAGE, snapshot.costUsage?.kind)
    }

    @Test
    fun `should show no cost when spend and extra usage are turned off`() {
        val snapshot = usage(
            """
            {
              "spend": { "enabled": false, "used": { "amount_minor": 541, "exponent": 2 } },
              "extra_usage": { "is_enabled": false, "used_credits": 541, "decimal_places": 2 }
            }
            """,
        )

        assertNull(snapshot.costUsage)
    }

    @Test
    fun `should still show the plan badge when Claude reports no usage`() {
        val snapshot = usage("{}", subscriptionType = "claude_max")

        assertTrue(snapshot.quotas.isEmpty())
        assertNull(snapshot.costUsage)
        assertEquals(AccountTier.ClaudeMax, snapshot.accountTier)
    }

    // Signed-in email

    @Test
    fun `should show the email Claude is signed in as when the API answers`() = claude { claude ->
        claude.writeClaudeConfig(email = "person@example.com", displayName = "Example Org")

        val usage = claude.readAPIResponse("""{ "five_hour": { "utilization": 25.0 } }""", subscriptionType = "claude_max")

        assertEquals("person@example.com", usage.accountEmail)
        assertEquals(75.0, usage.quota(QuotaType.Session)?.percentRemaining)
    }

    @Test
    fun `should still show the usage, without an email, when Claude keeps no account file`() {
        val usage = usage("""{ "five_hour": { "utilization": 25.0 } }""")

        assertNull(usage.accountEmail)
        assertEquals(75.0, usage.quota(QuotaType.Session)?.percentRemaining)
    }

    // Account tier

    @Test
    fun `should show the Max plan for a Max subscription`() {
        assertEquals(AccountTier.ClaudeMax, usage("""{ "five_hour": { "utilization": 10.0 } }""", subscriptionType = "claude_max").accountTier)
    }

    @Test
    fun `should show the Pro plan for a Pro subscription`() {
        assertEquals(AccountTier.ClaudePro, usage("""{ "five_hour": { "utilization": 10.0 } }""", subscriptionType = "claude_pro").accountTier)
    }

    // Errors

    @Test
    fun `should say the session expired when Claude refuses the login even after a refresh`() = claude { claude ->
        claude.writeCredentials()
        // The usage request and the refresh both answer 401.
        claude.answer { claudeResponse(401) }

        assertEquals(UsageError.SessionExpired(), claude.failure(claude.dataSource("api")))
    }

    @Test
    fun `should ask to sign in when Claude still forbids access after a refresh`() = claude { claude ->
        claude.writeCredentials()
        claude.answer { call ->
            if (call.isClaudeTokenRequest) claudeResponse(200, body = """{ "access_token": "new-token", "expires_in": 3600 }""")
            else claudeResponse(403)
        }

        assertEquals(UsageError.AuthenticationRequired, claude.failure(claude.dataSource("api")))
    }

    @Test
    fun `should fail to read the usage when Claude's answer is not JSON`() = claude { claude ->
        claude.writeCredentials()
        claude.answer { claudeResponse(200, body = "not json") }

        val error = claude.failure(claude.dataSource("api"))

        assertTrue(error is UsageError.ParseFailed, "Expected parseFailed, got $error")
    }

    @Test
    fun `should report a failed run when the network is down`() = claude { claude ->
        claude.writeCredentials()
        claude.answer { throw IOException("The Internet connection appears to be offline.") }

        val error = claude.failure(claude.dataSource("api"))

        assertTrue(error is UsageError.ExecutionFailed, "Expected executionFailed, got $error")
    }
}

/** The token refresh. */
class ClaudeAPITokenRefreshTest {

    private fun claude(test: (ClaudeHarness) -> Unit) {
        val claude = ClaudeHarness()
        try {
            test(claude)
        } finally {
            claude.cleanUp()
        }
    }

    /** Writes `~/.claude/.credentials.json` from inside a stub. */
    private fun writeCredentials(home: String, accessToken: String, refreshToken: String, expiresAt: Double) {
        writeClaudeCredentials(File(home, ".claude"), JsonObject(mapOf(
            "accessToken" to JsonPrimitive(accessToken),
            "refreshToken" to JsonPrimitive(refreshToken),
            "expiresAt" to claudeNumber(expiresAt),
        )))
    }

    @Test
    fun `should refresh an expired login, use it and save it back the way the CLI writes it`() = claude { claude ->
        // Token expired 1 hour ago
        val pastExpiry = (claude.now - 3600) * 1000
        claude.writeCredentials(accessToken = "old-token", expiresAt = pastExpiry, subscriptionType = "claude_max")
        val refreshResponse = """{ "access_token": "new-token", "refresh_token": "new-refresh-token", "expires_in": 3600 }"""
        claude.answer { call ->
            when {
                call.isClaudeTokenRequest -> claudeResponse(200, body = refreshResponse)
                // Only the refreshed token gets usage.
                call.claudeAuthorization != "Bearer new-token" -> claudeResponse(500)
                else -> claudeResponse(200, body = """{ "five_hour": { "utilization": 10.0 } }""")
            }
        }

        val snapshot = claude.fetchUsage(claude.dataSource("api"))

        assertEquals("claude", snapshot.providerId)
        assertEquals(90.0, snapshot.quotas.first().percentRemaining)
        val saved = claude.readCredentials()
        assertEquals("new-token", (saved["accessToken"] as? JsonPrimitive)?.content)
        assertEquals("new-refresh-token", (saved["refreshToken"] as? JsonPrimitive)?.content)
        assertEquals("claude_max", (saved["subscriptionType"] as? JsonPrimitive)?.content)
        // Claude Code reads expiresAt as a number of milliseconds.
        val expiresAt = saved["expiresAt"] as JsonPrimitive
        assertFalse(expiresAt.isString)
        val expected = ((claude.now + 3600) * 1000).toLong().toDouble()
        assertEquals(expected, expiresAt.double)
        // Nothing the CLI does not write is added.
        assertNull(saved["refreshedAt"])
    }

    @Test
    fun `should say the session expired when Claude revokes the refresh token`() = claude { claude ->
        claude.writeCredentials(expiresAt = (claude.now - 3600) * 1000)
        claude.answer { claudeResponse(400, body = """{ "error": "invalid_grant", "error_description": "Refresh token has been revoked" }""") }

        assertEquals(UsageError.SessionExpired(), claude.failure(claude.dataSource("api")))
    }

    @Test
    fun `should recover on the next refresh once the CLI has signed in again`() = claude { claude ->
        // Scenario: the stored refresh token is invalid, but the CLI has re-authenticated and
        // written new credentials to the file.
        claude.writeCredentials(accessToken = "old-token", expiresAt = (claude.now - 3600) * 1000)
        val refreshes = AtomicInteger()
        claude.answer { call ->
            if (call.isClaudeTokenRequest) {
                if (refreshes.incrementAndGet() == 1) {
                    // First refresh attempt: old token is invalid
                    claudeResponse(400, body = """{ "error": "invalid_grant", "error_description": "Refresh token has been revoked" }""")
                } else {
                    // Second refresh attempt (with fresh file credentials): success
                    claudeResponse(200, body = """{ "access_token": "brand-new-token", "refresh_token": "brand-new-refresh", "expires_in": 3600 }""")
                }
            } else {
                claudeResponse(200, body = """{ "five_hour": { "utilization": 15.0 } }""")
            }
        }
        val source = claude.dataSource("api")

        assertEquals(UsageError.SessionExpired(), claude.failure(source))

        // Simulate CLI re-authentication: write new credentials to file
        claude.writeCredentials(accessToken = "cli-refreshed-token", refreshToken = "cli-refreshed-refresh", expiresAt = (claude.now - 60) * 1000)

        val snapshot = claude.fetchUsage(source)

        assertEquals("claude", snapshot.providerId)
        assertEquals(85.0, snapshot.quotas.first().percentRemaining)
        assertEquals("brand-new-token", (claude.readCredentials()["accessToken"] as? JsonPrimitive)?.content)
    }

    @Test
    fun `should use the token the CLI wrote meanwhile when a refresh fails`() = claude { claude ->
        // Scenario: during a single fetch, the refresh fails but the CLI has updated the file in
        // the meantime with a different access token.
        claude.writeCredentials(accessToken = "stale-token", expiresAt = (claude.now - 3600) * 1000)
        val home = claude.home
        val futureExpiry = (claude.now + 3600) * 1000
        val refreshes = AtomicInteger()
        claude.answer { call ->
            when {
                call.isClaudeTokenRequest -> {
                    refreshes.incrementAndGet()
                    // Simulate the CLI updating the file concurrently
                    writeCredentials(home, "brand-new-token", "brand-new-refresh", futureExpiry)
                    claudeResponse(400, body = """{ "error": "invalid_grant", "error_description": "Token revoked" }""")
                }
                call.claudeAuthorization != "Bearer brand-new-token" -> claudeResponse(500)
                else -> claudeResponse(200, body = """{ "five_hour": { "utilization": 20.0 } }""")
            }
        }

        val snapshot = claude.fetchUsage(claude.dataSource("api"))

        assertEquals("claude", snapshot.providerId)
        assertEquals(80.0, snapshot.quotas.first().percentRemaining) // 100 - 20
        assertEquals(2, refreshes.incrementAndGet()) // only one refresh attempt was made before this
    }
}

/** A setup token in the environment. */
class ClaudeAPISetupTokenTest {

    private fun claude(test: (ClaudeHarness) -> Unit) {
        val claude = ClaudeHarness()
        try {
            test(claude)
        } finally {
            claude.cleanUp()
        }
    }

    @Test
    fun `should use a setup token from the environment without refreshing it`() = claude { claude ->
        claude.environment = mapOf("CLAUDE_CODE_OAUTH_TOKEN" to "setup-token-abc123")
        val usageResponse = """
            {
              "five_hour": { "utilization": 20.0, "resets_at": "2025-01-15T10:00:00Z" },
              "seven_day": { "utilization": 40.0, "resets_at": "2025-01-20T00:00:00Z" }
            }
        """
        // A refresh, were one tried, would expire the session.
        claude.answer { call ->
            if (call.isClaudeTokenRequest) claudeResponse(400, body = """{"error":"invalid_grant"}""")
            else claudeResponse(200, body = usageResponse)
        }

        val snapshot = claude.fetchUsage(claude.dataSource("api"))

        assertEquals("claude", snapshot.providerId)
        assertEquals(2, snapshot.quotas.size)
        assertEquals(80.0, snapshot.quotas.firstOrNull { it.quotaType == QuotaType.Session }?.percentRemaining) // 100 - 20
        assertEquals(60.0, snapshot.quotas.firstOrNull { it.quotaType == QuotaType.Weekly }?.percentRemaining) // 100 - 40
    }

    @Test
    fun `should send a setup token without its trailing newline`() = claude { claude ->
        claude.environment = mapOf("CLAUDE_CODE_OAUTH_TOKEN" to "setup-token-abc123\n")
        claude.answer { call ->
            if (call.claudeAuthorization == "Bearer setup-token-abc123") {
                claudeResponse(200, body = """{ "five_hour": { "utilization": 20.0, "resets_at": "2025-01-15T10:00:00Z" } }""")
            } else {
                claudeResponse(500)
            }
        }

        val snapshot = claude.fetchUsage(claude.dataSource("api"))

        assertEquals(80.0, snapshot.quotas.first().percentRemaining)
    }

    @Test
    fun `should ask to sign in, without refreshing, when Claude refuses a setup token`() = claude { claude ->
        claude.environment = mapOf("CLAUDE_CODE_OAUTH_TOKEN" to "expired-setup-token")
        // A refresh, were one possible, would hand out a working token.
        claude.answer { call ->
            when {
                call.isClaudeTokenRequest -> claudeResponse(200, body = """{ "access_token": "new-token", "expires_in": 3600 }""")
                call.claudeAuthorization == "Bearer new-token" -> claudeResponse(200, body = """{ "five_hour": { "utilization": 10.0 } }""")
                else -> claudeResponse(401)
            }
        }

        assertEquals(UsageError.AuthenticationRequired, claude.failure(claude.dataSource("api")))
    }

    @Test
    fun `should be available with a setup token in the environment`() = claude { claude ->
        claude.environment = mapOf("CLAUDE_CODE_OAUTH_TOKEN" to "my-setup-token")

        val source = claude.dataSource("api")

        assertTrue(source.hasKey)
        assertTrue(source.isReady())
    }
}
