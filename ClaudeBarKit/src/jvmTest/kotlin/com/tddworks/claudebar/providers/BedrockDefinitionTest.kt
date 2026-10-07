package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.CloudWatchClient
import com.tddworks.claudebar.datasources.PriceCatalog
import com.tddworks.claudebar.datasources.TEMP_HOME
import com.tddworks.claudebar.datasources.process.InMemoryLoginFolders
import com.tddworks.claudebar.datasources.testDataSources
import com.tddworks.claudebar.quotas.BudgetStatus
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.util.Collections

/**
 * Bedrock as data: today's CloudWatch token sums, priced from the Bedrock price list, as one
 * cost with a line per model. The daily budget judges that cost; it is never a quota.
 */
class BedrockDefinitionTest {
    private class Seen {
        val regions: MutableList<String> = Collections.synchronizedList(mutableListOf())
        val profiles: MutableList<String?> = Collections.synchronizedList(mutableListOf())
    }

    private val usual = mapOf(
        "us-east-1" to mapOf(
            "anthropic.claude-sonnet-4" to mapOf("InputTokenCount" to 1_000_000.0, "OutputTokenCount" to 200_000.0, "Invocations" to 40.0),
            "us.amazon.nova-pro-v1:0" to mapOf("InputTokenCount" to 500_000.0, "OutputTokenCount" to 0.0, "Invocations" to 10.0),
        ),
    )

    private fun make(
        regions: String? = null, profile: String? = null, budget: String? = null,
        sums: Map<String, Map<String, Map<String, Double>>> = usual, seen: Seen = Seen(),
    ): Provider {
        val client = object : CloudWatchClient {
            override suspend fun sums(
                namespace: String, dimension: String, metrics: List<String>, region: String, profile: String?,
                fromSeconds: Double, toSeconds: Double,
            ): Map<String, Map<String, Double>> {
                if (namespace != "AWS/Bedrock" || dimension != "ModelId") return emptyMap()
                seen.regions += region
                seen.profiles += profile
                return sums[region] ?: emptyMap()
            }
        }
        val catalog = object : PriceCatalog {
            override suspend fun prices(service: String, ids: List<String>): Map<String, Map<String, String>> =
                if (service != "AmazonBedrock") emptyMap() else mapOf(
                    "anthropic.claude-sonnet-4" to mapOf("input" to "3", "output" to "15", "per" to "1000000", "name" to "Claude Sonnet 4"),
                    "us.amazon.nova-pro-v1:0" to mapOf("input" to "0.8", "output" to "3.2", "per" to "1000000", "name" to "Nova Pro"),
                )
        }
        val settings = InMemoryProviderSettings()
        settings.setValue(regions, "regions", "bedrock")
        settings.setValue(profile, "awsProfile", "bedrock")
        settings.setValue(budget, "dailyBudget", "bedrock")
        val definition = TestDefinitions.builtIn("bedrock")
        val connections = testDataSources(cloudWatch = client, priceCatalog = catalog, now = { System.currentTimeMillis() / 1000.0 })
        return Provider(
            definition = definition, settings = settings,
            makeDataSource = { source, _ -> connections.make(source, definition.id, null, TestDefinitions.builtIns::script) },
            folders = InMemoryLoginFolders(), paths = HomePaths(TEMP_HOME), isExecutable = { true }, locate = { it },
        )
    }

    @Test
    fun `should keep Bedrock's name and dashboard, off until the person turns it on`() {
        val provider = make()
        assertEquals("AWS Bedrock", provider.name)
        assertFalse(provider.plainIsInLineup)
        assertEquals("https://console.aws.amazon.com/bedrock/home", provider.plainDashboardURL)
    }

    @Test
    fun `should show today's spend as one exact cost with a line per model, largest first`() {
        val usage = make().refreshPlain().usage()
        val cost = usage.costUsage
        assertNotNull(cost)
        // 1M × $3 + 0.2M × $15 = $6; 0.5M × $0.80 = $0.40.
        assertEquals(6_400_000_000, cost!!.totalCostNanos)
        assertEquals(listOf("Claude Sonnet 4", "Nova Pro"), cost.lines.map { it.label })
        assertEquals(listOf(6_000_000_000, 400_000_000), cost.lines.map { it.amountNanos })
        assertEquals("1.2M tokens · 40 calls", cost.lines.first().detail)
        assertEquals("Today", cost.resetText)
        // Money gone is never a quota.
        assertTrue(usage.quotas.isEmpty())
    }

    @Test
    fun `should judge the cost against the daily budget, never as a quota`() {
        val usage = make(budget = "10").refreshPlain().usage()
        val cost = usage.costUsage
        assertNotNull(cost)
        assertEquals(10_000_000_000, cost!!.budgetNanos)
        assertEquals(BudgetStatus.from(6_400_000_000, 10_000_000_000), cost.budgetStatusFromBuiltIn)
        assertTrue(usage.quotas.isEmpty())
    }

    @Test
    fun `should ask every region the person named, with their profile`() {
        val seen = Seen()
        make(regions = "us-east-1, eu-west-1", profile = "work", seen = seen).refreshPlain()
        assertEquals(listOf("us-east-1", "eu-west-1"), seen.regions)
        assertEquals(listOf("work", "work"), seen.profiles)
    }

    @Test
    fun `should use the default credentials in us-east-1 when the person names no profile or region`() {
        val seen = Seen()
        make(seen = seen).refreshPlain()
        assertEquals(listOf("us-east-1"), seen.regions)
        assertEquals(listOf<String?>(null), seen.profiles)
    }

    @Test
    fun `should show a model with no known price as a line of nothing, and say so`() {
        val usage = make(sums = mapOf("us-east-1" to mapOf("acme.mystery" to mapOf("InputTokenCount" to 10.0, "Invocations" to 1.0)))).refreshPlain().usage()
        val line = usage.costUsage?.lines?.firstOrNull()
        assertNotNull(line)
        assertEquals(0L, line!!.amountNanos)
        assertEquals("10 tokens · 1 calls · no price known", line.detail)
    }

    @Test
    fun `should show $0 when nothing was used today, not a missing cost`() {
        val usage = make(sums = emptyMap()).refreshPlain().usage()
        assertEquals(0L, usage.costUsage?.totalCostNanos)
        assertEquals(true, usage.costUsage?.lines?.isEmpty())
    }
}
