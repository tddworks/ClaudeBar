package com.tddworks.claudebar.datasources.fetch

import com.tddworks.claudebar.datasources.CloudWatchCall
import com.tddworks.claudebar.datasources.CloudWatchClient
import com.tddworks.claudebar.datasources.Credential
import com.tddworks.claudebar.datasources.Fetching
import com.tddworks.claudebar.datasources.PriceCatalog
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.diagnostics.AppLog
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * `cloudWatch` — today's sums, one row per dimension value in each region, priced when the
 * call names a price list. A region that fails is logged and left out; every region failing
 * is the failure. Today starts at local midnight, as the person counts a day.
 */
internal class CloudWatchFetcher(
    val call: CloudWatchCall,
    private val client: CloudWatchClient?,
    private val catalog: PriceCatalog?,
    private val now: () -> Double,
    private val startOfDay: (Double) -> Double = ::startOfLocalDaySeconds,
) : Fetching {
    override fun isReady() = client != null && call.regionList.isNotEmpty()

    override suspend fun fetch(credential: Credential?): Response {
        val client = client ?: throw UsageError.ExecutionFailed("This build can't read cloud metrics")
        val regions = call.regionList
        if (regions.isEmpty()) throw UsageError.ExecutionFailed("No regions configured")
        val end = now()
        val start = startOfDay(end)

        val rows = mutableListOf<JsonObject>()
        var firstError: Exception? = null
        var answered = false
        for (region in regions) {
            try {
                val sums = client.sums(call.namespace, call.dimension, call.metrics, region, call.profileName, start, end)
                answered = true
                for ((id, metrics) in sums.sortedByKey()) {
                    val row = mutableMapOf<String, JsonElement>("id" to JsonPrimitive(id), "region" to JsonPrimitive(region))
                    for ((name, value) in metrics) row[name] = JsonPrimitive(value)
                    rows += JsonObject(row.sortedByKey())
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                AppLog.probes.warning("${call.namespace} metrics in $region failed: ${error.message}")
                firstError = firstError ?: error
            }
        }
        if (!answered) firstError?.let { throw it }

        val body = mutableMapOf<String, JsonElement>("rows" to JsonArray(rows), "periodStart" to JsonPrimitive(start))
        val service = call.prices
        if (service != null && catalog != null) {
            val ids = rows.mapNotNull { (it["id"] as? JsonPrimitive)?.content }.toSet().sorted()
            val prices = if (ids.isEmpty()) emptyMap() else catalog.prices(service, ids)
            body["prices"] = JsonObject(prices.sortedByKey().mapValues { (_, fields) -> JsonObject(fields.sortedByKey().mapValues { JsonPrimitive(it.value) }) })
        }
        return Response(body = JsonObject(body.sortedByKey()).toString().encodeToByteArray())
    }
}

/** The start of the local calendar day holding [seconds] (since 1970), in seconds since 1970. */
internal expect fun startOfLocalDaySeconds(seconds: Double): Double

/** Keys in order, so the body reads the same every time. */
private fun <V> Map<String, V>.sortedByKey(): Map<String, V> = entries.sortedBy { it.key }.associate { it.key to it.value }
