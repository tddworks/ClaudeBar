package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.HttpCall
import com.tddworks.claudebar.datasources.NetworkClient
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.datasources.process.InMemoryLoginFolders
import com.tddworks.claudebar.datasources.testDataSources
import com.tddworks.claudebar.quotas.AccountTier
import com.tddworks.claudebar.quotas.Left
import com.tddworks.claudebar.quotas.Money
import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageError
import com.tddworks.claudebar.quotas.UsageSnapshot
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.CsvSource
import org.junit.jupiter.params.provider.ValueSource
import java.io.File
import java.time.Instant
import java.time.OffsetDateTime
import java.util.Collections

/** Grok as data: the billing response read by `grok-billing.js` — the old probe's fixtures, quota for quota. */
class GrokDefinitionTest {
    /** Each request that wasn't Grok's billing or settings with the login's token — checked after every test. */
    private val wrongRequests: MutableList<String> = Collections.synchronizedList(mutableListOf())

    @AfterEach
    fun `every request is Grok's, with the login's token`() {
        assertEquals(emptyList<String>(), wrongRequests)
    }

    private fun HttpCall.header(name: String): String? = headers.entries.firstOrNull { it.key.equals(name, ignoreCase = true) }?.value

    private fun parseOutcome(data: String, accountEmail: String? = null, settings: String = "{}", settingsStatus: Int = 200): RefreshOutcome {
        val root = TestDefinitions.folder("grok")
        try {
            val folder = File(root, ".grok").apply { mkdirs() }
            val entry = buildMap<String, JsonElement> {
                put("key", JsonPrimitive("fixture-token"))
                if (accountEmail != null) put("email", JsonPrimitive(accountEmail))
            }
            File(folder, "auth.json").writeText(JsonObject(mapOf("fixture-entry" to JsonObject(entry))).toString())
            val network = object : NetworkClient {
                override suspend fun send(call: HttpCall): Response {
                    if (call.header("Authorization") != "Bearer fixture-token") wrongRequests += "token ${call.header("Authorization")}"
                    if (call.url == "https://cli-chat-proxy.grok.com/v1/settings") return Response(settingsStatus, body = settings.encodeToByteArray())
                    if (call.url != "https://cli-chat-proxy.grok.com/v1/billing?format=credits") wrongRequests += "url ${call.url}"
                    return Response(200, body = data.encodeToByteArray())
                }
            }
            val connections = testDataSources(network = network, home = root.path, now = { System.currentTimeMillis() / 1000.0 })
            val provider = Provider(
                definition = TestDefinitions.builtIn("grok"), settings = InMemoryProviderSettings(),
                makeDataSource = { source, _ -> connections.make(source, "grok", null, TestDefinitions.builtIns::script) },
                folders = InMemoryLoginFolders(), paths = HomePaths(root.path), isExecutable = { true }, locate = { it },
            )
            return provider.refreshPlain()
        } finally {
            root.deleteRecursively()
        }
    }

    private fun parse(data: String, accountEmail: String? = null, settings: String = "{}", settingsStatus: Int = 200): UsageSnapshot =
        parseOutcome(data, accountEmail, settings, settingsStatus).usage()

    private fun productName(name: String): String {
        val data = JsonObject(mapOf("productUsage" to JsonArray(listOf(JsonObject(mapOf("product" to JsonPrimitive(name), "usagePercent" to JsonPrimitive(10)))))))
        val quota = parse(data.toString()).quotas.firstOrNull()
        assertNotNull(quota)
        return quota!!.quotaType.displayName
    }

    /** A date as `OAuth2Refresher.parseDate` reads it: ISO 8601, to the millisecond. */
    private fun seconds(iso: String): Double = OffsetDateTime.parse(iso).toInstant().toEpochMilli() / 1000.0

    /** Real response shape from `GET /v1/billing?format=credits`. */
    private val sampleResponse = """
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
    """.trimIndent()

    @Test
    fun `should show the weekly credits, each product and the prepaid balance, and no on-demand while its cap is zero`() {
        val snapshot = parse(sampleResponse)

        assertEquals("grok", snapshot.providerId)
        // Weekly credits + 3 products + prepaid $2.49; on-demand skipped while its cap is 0
        assertEquals(5, snapshot.quotas.size)
        assertEquals(Left.Balance(Money(2_490_000_000, "USD"), null), snapshot.quotas.last().left)
    }

    @Test
    fun `should show the weekly credits left`() {
        val weekly = parse(sampleResponse).quota(QuotaType.Weekly)
        assertNotNull(weekly)
        assertEquals(4.0, weekly!!.percentRemaining) // 100 - 96
    }

    @Test
    fun `should show what is left of Build, Imagine and Voice`() {
        val snapshot = parse(sampleResponse)

        assertEquals(16.0, snapshot.quota(QuotaType.ModelSpecific("Build"))?.percentRemaining) // 100 - 84
        assertEquals(89.0, snapshot.quota(QuotaType.ModelSpecific("Imagine"))?.percentRemaining) // 100 - 11
        assertEquals(99.0, snapshot.quota(QuotaType.ModelSpecific("Voice"))?.percentRemaining) // 100 - 1
    }

    @Test
    fun `should reset the credits when the weekly billing period ends`() {
        val weekly = parse(sampleResponse).quota(QuotaType.Weekly)
        assertNotNull(weekly)
        assertEquals(seconds("2026-07-30T05:09:24.881042+00:00"), weekly!!.resetsAtSeconds)
        assertEquals((7 * 24 * 3600).toDouble(), weekly.windowSeconds)
    }

    @Test
    fun `should show the login's email`() {
        assertEquals("user@example.com", parse(sampleResponse, accountEmail = "user@example.com").accountEmail)
    }

    @Test
    fun `should show the credits as monthly when the billing period is monthly`() {
        val json = """
            {
              "config": {
                "currentPeriod": {"type": "USAGE_PERIOD_TYPE_MONTHLY"},
                "creditUsagePercent": 50.0
              }
            }
        """.trimIndent()

        val quota = parse(json).quotas.firstOrNull()
        assertNotNull(quota)
        assertEquals(QuotaType.TimeLimit("Monthly"), quota!!.quotaType)
        assertEquals(50.0, quota.percentRemaining)
    }

    @Test
    fun `should show on-demand spend once it has a cap`() {
        val json = """
            {
              "config": {
                "currentPeriod": {"type": "USAGE_PERIOD_TYPE_WEEKLY"},
                "creditUsagePercent": 10.0,
                "onDemandCap": {"val": 100},
                "onDemandUsed": {"val": 25}
              }
            }
        """.trimIndent()

        val onDemand = parse(json).quota(QuotaType.TimeLimit("On-Demand"))
        assertNotNull(onDemand)
        assertEquals(75.0, onDemand!!.percentRemaining)
    }

    @Test
    fun `should show the credits as Usage, with no guessed window, when no period is stated`() {
        val json = """
            {
              "config": {
                "creditUsagePercent": 96,
                "productUsage": [{"product": "GrokBuild", "usagePercent": 84}]
              }
            }
        """.trimIndent()

        val snapshot = parse(json)

        assertEquals(2, snapshot.quotas.size)
        // No period stated: "Usage", never a guessed weekly window.
        assertEquals(4.0, snapshot.quota(QuotaType.TimeLimit("Usage"))?.percentRemaining)
        assertNull(snapshot.quota(QuotaType.TimeLimit("Usage"))?.window?.lengthSeconds)
    }

    @Test
    fun `should show no quotas when Grok reports nothing`() {
        assertTrue(parse("{}").quotas.isEmpty())
    }

    @Test
    fun `should show no quota, not a made-up 100%, when billing names a period but no usage`() {
        val json = """
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
        """.trimIndent()

        // No usage reported is no quota — never a made-up 100% (the Left law).
        assertTrue(parse(json).quotas.isEmpty())
    }

    @Test
    fun `should fail when Grok's billing answer isn't JSON`() {
        val outcome = parseOutcome("not json")
        assertTrue(outcome is RefreshOutcome.Failed, "$outcome")
        assertEquals(UsageError.ParseFailed("Failed to parse billing response as JSON"), (outcome as RefreshOutcome.Failed).error)
    }

    // Product names

    @Test
    fun `should name Grok's products without the Grok prefix`() {
        assertEquals("Build", productName("GrokBuild"))
        assertEquals("Imagine", productName("GrokImagine"))
        assertEquals("Voice", productName("GrokVoice"))
    }

    @Test
    fun `should name an unknown product in separate words`() {
        assertEquals("Some New Product", productName("SomeNewProduct"))
    }

    @Test
    fun `should name a product called just Grok as Grok`() {
        assertEquals("Grok", productName("Grok"))
    }

    // Plan, prepaid balance and billing period

    private fun billing(vararg config: Pair<String, JsonElement>): String = JsonObject(mapOf("config" to JsonObject(config.toMap()))).toString()

    @Test
    fun `should show the plan Grok's settings name`() {
        val usage = parse(billing("creditUsagePercent" to JsonPrimitive(10)), settings = """{"subscription_tier_display":"SuperGrok Heavy"}""")
        assertEquals(AccountTier.Custom("SuperGrok Heavy"), usage.accountTier)
    }

    @ParameterizedTest
    @CsvSource("SUPERGROK_HEAVY, SuperGrok Heavy", "supergrok, SuperGrok", "Grok Team, Grok Team")
    fun `should name the plan from billing when Grok's settings don't`(tier: String, plan: String) {
        val usage = parse(billing("creditUsagePercent" to JsonPrimitive(10), "subscriptionTier" to JsonPrimitive(tier)))
        assertEquals(AccountTier.Custom(plan), usage.accountTier)
    }

    @Test
    fun `should still show the credits when Grok's settings can't be read`() {
        val usage = parse(billing("creditUsagePercent" to JsonPrimitive(10)), settings = "oops", settingsStatus = 500)
        assertEquals(90.0, usage.quotas.firstOrNull()?.percentRemaining)
        assertNull(usage.accountTier)
    }

    @Test
    fun `should show the prepaid balance in dollars`() {
        val usage = parse(billing("creditUsagePercent" to JsonPrimitive(10), "prepaidBalance" to JsonObject(mapOf("val" to JsonPrimitive("2490")))))
        val prepaid = usage.quotas.firstOrNull { it.quotaType == QuotaType.ModelSpecific("Prepaid") }
        assertNotNull(prepaid)
        assertEquals(Left.Balance(Money(24_900_000_000, "USD"), null), prepaid!!.left)
    }

    @ParameterizedTest
    @ValueSource(strings = ["{}", """{"val":0}"""])
    fun `should leave out an empty prepaid balance rather than show it depleted`(balance: String) {
        val usage = parse("""{"config":{"creditUsagePercent":10,"prepaidBalance":$balance}}""")
        assertFalse(usage.quotas.any { it.quotaType == QuotaType.ModelSpecific("Prepaid") })
    }

    @Test
    fun `should reset at the billing period's end when Grok names no current period`() {
        val usage = parse(
            billing(
                "creditUsagePercent" to JsonPrimitive(10),
                "billingPeriodStart" to JsonPrimitive("2026-07-01T00:00:00+00:00"),
                "billingPeriodEnd" to JsonPrimitive("2026-08-01T00:00:00+00:00"),
            ),
        )
        val credits = usage.quotas.firstOrNull()
        assertNotNull(credits)
        assertEquals(Instant.parse("2026-08-01T00:00:00Z").epochSecond.toDouble(), credits!!.resetsAtSeconds)
        assertEquals((31 * 86400).toDouble(), credits.windowSeconds ?: -1.0)
    }
}
