package com.tddworks.claudebar.datasources.fetch

import com.tddworks.claudebar.datasources.CloudWatchCall
import com.tddworks.claudebar.datasources.CloudWatchClient
import com.tddworks.claudebar.datasources.Fetch
import com.tddworks.claudebar.datasources.PriceCatalog
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/** Today's cloud metrics, summed per dimension value in each region and priced from the cloud's own list. */
class CloudWatchFetchTest {
    private val call = CloudWatchCall(
        namespace = "Acme/Models", dimension = "ModelId", metrics = listOf("In", "Out"),
        regions = "east-1, west-2", profile = "work", prices = "AcmeModels",
    )
    private val noon = 1_767_268_800.0 // a fixed moment

    data class Asked(val region: String, val profile: String?, val from: Double, val to: Double)

    /** Answers the same sums in every region but those [failing]. */
    internal class Metrics(private val failing: Set<String> = emptySet()) : CloudWatchClient {
        val asked = mutableListOf<Asked>()
        override suspend fun sums(
            namespace: String, dimension: String, metrics: List<String>, region: String, profile: String?,
            fromSeconds: Double, toSeconds: Double,
        ): Map<String, Map<String, Double>> {
            asked += Asked(region, profile, fromSeconds, toSeconds)
            if (region in failing) throw UsageError.ExecutionFailed("denied in $region")
            return mapOf("acme.small" to mapOf("In" to 1000.0, "Out" to 50.0))
        }
    }

    internal class Prices : PriceCatalog {
        override suspend fun prices(service: String, ids: List<String>) =
            mapOf("acme.small" to mapOf("in" to "3", "out" to "15", "per" to "1000000"))
    }

    private suspend fun fetch(call: CloudWatchCall, metrics: Metrics = Metrics()): JsonObject {
        val response = CloudWatchFetcher(call, metrics, Prices(), { noon }).fetch(null)
        return Json.parseToJsonElement(response.text) as JsonObject
    }

    @Test
    fun `should total today's usage per region under the chosen profile, priced from the cloud's own list`() = runTest {
        val metrics = Metrics()
        val body = fetch(call, metrics)
        val rows = body["rows"]!!.jsonArray.map { it.jsonObject }

        assertEquals(listOf("east-1", "west-2"), rows.map { it["region"]!!.jsonPrimitive.content })
        assertEquals(1000.0, rows.first()["In"]!!.jsonPrimitive.double)
        assertEquals("15", body["prices"]!!.jsonObject["acme.small"]!!.jsonObject["out"]!!.jsonPrimitive.content)
        assertEquals(listOf("work", "work"), metrics.asked.map { it.profile })
        assertEquals(startOfLocalDaySeconds(noon), metrics.asked.first().from)
        assertEquals(noon, metrics.asked.first().to)
    }

    @Test
    fun `should leave out a region the cloud refuses and show the others`() = runTest {
        val rows = fetch(call, Metrics(failing = setOf("west-2")))["rows"]!!.jsonArray
        assertEquals(listOf("east-1"), rows.map { it.jsonObject["region"]!!.jsonPrimitive.content })
    }

    @Test
    fun `should fail with the cloud's reason when every region refuses`() = runTest {
        val error = try {
            fetch(call, Metrics(failing = setOf("east-1", "west-2")))
            null
        } catch (error: UsageError) {
            error
        }
        assertEquals(UsageError.ExecutionFailed("denied in east-1"), error)
    }

    @Test
    fun `should use the default credentials when no profile is set, and not be ready when no region is set`() = runTest {
        val metrics = Metrics()
        fetch(CloudWatchCall("N", "D", listOf("M"), regions = "east-1", profile = "{{setting.profile}}"), metrics)
        assertNull(metrics.asked.first().profile)

        val blank = CloudWatchFetcher(CloudWatchCall("N", "D", listOf("M"), regions = "{{setting.regions}}"), Metrics(), null, { noon })
        assertFalse(blank.isReady())
    }

    @Test
    fun `should keep a cloud-metrics fetch when the definition is written out and read back`() {
        val fetch = Fetch.CloudWatch(call)
        assertEquals(fetch, Fetch.from(fetch.toJson()))
    }
}
