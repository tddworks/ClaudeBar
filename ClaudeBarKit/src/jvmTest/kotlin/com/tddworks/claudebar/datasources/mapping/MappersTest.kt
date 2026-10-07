package com.tddworks.claudebar.datasources.mapping

import com.tddworks.claudebar.datasources.MappingFacts
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.quotas.AccountTier
import com.tddworks.claudebar.quotas.CostUsage
import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageError
import com.tddworks.claudebar.quotas.UsageSnapshot
import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows

/** The JSON and text mappers on their own — the mapping cases of DataSourceTests, read at the mapper. */
class MappersTest {
    private val now = 1_700_000_000.0
    private val dollar = 1_000_000_000L

    private fun read(mapping: String, body: String, headers: Map<String, String> = emptyMap()): UsageSnapshot =
        Mapping.from(Json.parseToJsonElement(mapping)).reader({ null }, NoScriptEngine, { now })
            .read(Response(status = 200, headers = headers, body = body.encodeToByteArray()), MappingFacts(), "test")

    @Test
    fun `should fail at reading the answer when the server doesn't answer in JSON`() {
        val error = assertThrows<UsageError.ParseFailed> { read("""{"json":{"quotas":[]}}""", "<html>") }
        assertEquals("Response is not JSON", error.reason)
    }

    @Test
    fun `should show a credit balance as money left with a budget and no reset`() {
        val usage = read(
            """{"json":{"quotas":[{"kind":"model","name":"Credits","at":"$.data","leftPercent":"left"}],
                        "cost":{"used":"$.data.usage","limit":"$.data.limit"}}}""",
            """{"data":{"left":24.8,"usage":37.6,"limit":50}}""",
        )

        assertEquals(24.8, usage.quota(QuotaType.ModelSpecific("Credits"))?.percentRemaining)
        assertNull(usage.quota(QuotaType.ModelSpecific("Credits"))?.resetsAtSeconds)
        assertEquals(50 * dollar, usage.costUsage?.budgetNanos)
        assertEquals(37_600_000_000L, usage.costUsage?.totalCostNanos)
    }

    @Test
    fun `should name each repeated quota from the answer, tidied, and skip one with no name`() {
        val usage = read(
            """{"json":{"quotas":[{"kind":"time","each":"$.limits",
               "name":{"firstOf":["name"],"dropPrefixes":[{"prefix":"vendor_","capitalize":true}]},
               "usedPercent":"used"}]}}""",
            """{"limits":[{"name":"vendor_spark","used":40},{"name":"","used":1}]}""",
        )

        assertEquals(listOf(QuotaType.TimeLimit("Spark")), usage.quotas.map { it.quotaType })
        assertEquals(60.0, usage.quotas.first().percentRemaining)
    }

    @Test
    fun `should show when a quota resets as a countdown when the answer gives seconds from now`() {
        val quota = read(
            """{"json":{"quotas":[{"kind":"session","usedPercent":"used","resetsAt":{"secondsFromNow":"in"}}]}}""",
            """{"used":10,"in":5400}""",
        ).quota(QuotaType.Session)

        assertEquals(1_700_005_400.0, quota?.resetsAtSeconds)
        assertEquals("Resets in 1h 30m", quota?.resetText)
    }

    @Test
    fun `should ask to sign in when the CLI screen says to log in, even beside its numbers`() {
        assertThrows<UsageError.AuthenticationRequired> {
            read(
                """{"text":{"errors":[{"contains":["please log in"],"error":"authenticationRequired"}],
                            "quotas":[{"kind":"session","label":"5h limit","leftPercent":"([0-9]+)% left"}]}}""",
                "5h limit 80% left\nPlease log in",
            )
        }
    }

    @Test
    fun `should read each quota on a terminal screen near its label, past the colour codes`() {
        val usage = read(
            """{"text":{"quotas":[{"kind":"session","label":"5h limit","leftPercent":"([0-9]{1,3})%\\s+left"},
                                 {"kind":"weekly","label":"Weekly limit","usedPercent":"([0-9]{1,3})% used"}]}}""",
            "\u001B[1m5h limit\u001B[0m\n  [####] 72%  left\nWeekly limit\n30% used",
        )

        assertEquals(72.0, usage.quota(QuotaType.Session)?.percentRemaining)
        assertEquals(70.0, usage.quota(QuotaType.Weekly)?.percentRemaining)
    }

    @Test
    fun `should say what the screen lacks when no quota is on it`() {
        val error = assertThrows<UsageError.ParseFailed> {
            read("""{"text":{"quotas":[{"kind":"session","label":"5h limit","leftPercent":"([0-9]+)% left"}],"whenEmpty":"No limits yet"}}""", "hello")
        }
        assertEquals("No limits yet", error.reason)
    }

    @Test
    fun `should show only the elements that match, each window with its own suffix`() {
        val usage = read(
            """{"json":{"quotas":[{"kind":"time","each":"$.byId","skipKeys":["main"],"name":{"firstOf":["${'$'}key"]},
               "where":{"path":"on","equals":true},"windows":[{"at":"primary"},{"at":"secondary","suffix":" 7d"}],
               "usedPercent":"used","window":[{"minutes":"mins"},{"days":7}]}]}}""",
            """{"byId":{"main":{"on":true,"primary":{"used":1}},"spark":{"on":true,"primary":{"used":10,"mins":300},"secondary":{"used":20}},
               "off":{"on":false,"primary":{"used":5}}}}""",
        )

        assertEquals(listOf(QuotaType.TimeLimit("spark"), QuotaType.TimeLimit("spark 7d")), usage.quotas.map { it.quotaType })
        assertEquals(listOf(18000.0, 604800.0), usage.quotas.map { it.windowSeconds })
    }

    @Test
    fun `should keep only the first quota of a kind and name when a rule says unique`() {
        val usage = read(
            """{"json":{"quotas":[{"kind":"model","name":"opus","at":"$.a","usedPercent":"used"},
               {"kind":"model","each":"$.list","name":{"firstOf":["model"],"firstWord":true,"lowercase":true},"usedPercent":"used","unique":true}]}}""",
            """{"a":{"used":10},"list":[{"model":"Opus 4","used":50},{"model":"Sonnet 4","used":30}]}""",
        )

        assertEquals(listOf(90.0, 70.0), usage.quotas.map { it.percentRemaining })
        assertEquals(listOf(QuotaType.ModelSpecific("opus"), QuotaType.ModelSpecific("sonnet")), usage.quotas.map { it.quotaType })
    }

    @Test
    fun `should show a fixed quota when nothing answered and the plan says why`() {
        val mapping = """{"json":{"quotas":[{"kind":"session","at":"$.limits","usedPercent":"used"}],
            "whenEmpty":{"if":{"path":"$.plan","equals":"free"},"quotas":[{"kind":"session","usedPercent":0,"resetText":"Free plan"}],
                         "otherwise":"No rate limits yet"}}}"""

        val free = read(mapping, """{"plan":"free"}""").quota(QuotaType.Session)
        val error = assertThrows<UsageError.ParseFailed> { read(mapping, """{"plan":"pro"}""") }

        assertEquals(100.0, free?.percentRemaining)
        assertEquals("Free plan", free?.resetText)
        assertEquals("No rate limits yet", error.reason)
    }

    @Test
    fun `should read used percent from a header first, and over the limit as negative only when told`() {
        val usage = read(
            """{"json":{"quotas":[{"kind":"session","usedPercent":["${'$'}header.x-used","used"]},
                                 {"kind":"weekly","usedPercent":"over","overLimit":true}]}}""",
            """{"used":10,"over":120}""",
            headers = mapOf("X-Used" to "25"),
        )

        assertEquals(75.0, usage.quota(QuotaType.Session)?.percentRemaining)
        assertEquals(-20.0, usage.quota(QuotaType.Weekly)?.percentRemaining)
    }

    @Test
    fun `should count down in hours, or in days, to an ISO 8601 reset`() {
        val hours = read(
            """{"json":{"quotas":[{"kind":"weekly","usedPercent":"u","resetsAt":{"iso8601":"r"},"countdown":"hours"}]}}""",
            """{"u":1,"r":"2023-11-17T22:13:20.5Z"}""",
        ).quota(QuotaType.Weekly)
        val days = read(
            """{"json":{"quotas":[{"kind":"weekly","usedPercent":"u","resetsAt":{"iso8601":"r"}}]}}""",
            """{"u":1,"r":"2023-11-17T22:13:20Z"}""",
        ).quota(QuotaType.Weekly)

        assertEquals("Resets in 72h 0m", hours?.resetText)
        assertEquals(1_700_259_200.5, hours?.resetsAtSeconds)
        assertEquals("Resets in 3d 0h 0m", days?.resetText)
    }

    @Test
    fun `should show the plan by its badge, or as a well-known plan by name`() {
        val badge = read("""{"json":{"plan":{"path":"$.plan","badges":{"plus":"Plus+"}}}}""", """{"plan":"Plus"}""")
        val shouted = read("""{"json":{"plan":"$.plan"}}""", """{"plan":"team"}""")
        val known = read("""{"json":{"plan":{"path":"$.plan","plans":{"max":"claudeMax"}}}}""", """{"plan":"MAX"}""")

        assertEquals(AccountTier.Custom("Plus+"), badge.accountTier)
        assertEquals(AccountTier.Custom("TEAM"), shouted.accountTier)
        assertEquals(AccountTier.ClaudeMax, known.accountTier)
    }

    @Test
    fun `should show extra usage in minor units only while it is turned on`() {
        val mapping = """{"json":{"cost":{"kind":"extraUsage","when":{"path":"$.on","equals":true},
            "used":{"amount":"$.used","decimals":"$.exp"},"limit":{"amount":"$.limit","decimals":2}}}}"""

        val on = read(mapping, """{"on":true,"used":1234,"exp":2,"limit":5000}""").costUsage
        val off = read(mapping, """{"on":false,"used":1234,"exp":2,"limit":5000}""").costUsage
        val badLimit = read(mapping, """{"on":true,"used":1234,"exp":2,"limit":"5000"}""").costUsage

        assertEquals(CostUsage.Kind.EXTRA_USAGE, on?.kind)
        assertEquals(12_340_000_000L, on?.totalCostNanos)
        assertEquals(50 * dollar, on?.budgetNanos)
        assertNull(off)
        assertNull(badLimit)
    }

    @Test
    fun `should show money used as what is gone from the limit`() {
        val cost = read(
            """{"json":{"cost":{"remaining":["${'$'}header.balance","$.balance"],"limit":1000}}}""",
            """{"balance":"250.5"}""",
        ).costUsage

        assertEquals(749_500_000_000L, cost?.totalCostNanos)
        assertEquals(1000 * dollar, cost?.budgetNanos)
    }

    @Test
    fun `should refuse an answer that is JSON but not an object when the mapping says so`() {
        val error = assertThrows<UsageError.ParseFailed> { read("""{"json":{"notAnObject":"Not usage"}}""", "[1,2]") }
        assertEquals("Not usage", error.reason)
    }
}
