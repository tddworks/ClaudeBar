package com.tddworks.claudebar.datasources.fetch.aws

import com.tddworks.claudebar.datasources.HttpCall
import com.tddworks.claudebar.datasources.NetworkClient
import com.tddworks.claudebar.datasources.Response
import io.ktor.http.decodeURLQueryComponent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** CloudWatch and the price list over a signed request, without the AWS SDK. */
class AWSClientsTest {
    private val keys = mapOf("AWS_ACCESS_KEY_ID" to "AKIDEXAMPLE", "AWS_SECRET_ACCESS_KEY" to "secret")
    private val now = 1_767_268_800.0

    internal class Endpoint(private val answer: (HttpCall, Map<String, String>) -> Response) : NetworkClient {
        val sent = mutableListOf<HttpCall>()
        override suspend fun send(call: HttpCall): Response {
            sent += call
            val form = call.body?.decodeToString().orEmpty().split('&').filter { '=' in it }
                .associate { it.substringBefore('=').decodeURLQueryComponent() to it.substringAfter('=').decodeURLQueryComponent() }
            return answer(call, form)
        }
    }

    private fun xml(text: String) = Response(200, body = text.encodeToByteArray())

    private fun metrics(vararg ids: String) = ids.joinToString("") {
        "<member><Namespace>Acme/Models</Namespace><MetricName>In</MetricName><Dimensions>" +
            "<member><Name>Region</Name><Value>x</Value></member><member><Name>ModelId</Name><Value>$it</Value></member>" +
            "</Dimensions></member>"
    }

    private val cloudWatch = Endpoint { _, form ->
        when (form["Action"]) {
            "ListMetrics" -> if (form["NextToken"] == null) {
                xml("<ListMetricsResponse><ListMetricsResult><Metrics>${metrics("acme.small", "acme.big")}</Metrics><NextToken>page2</NextToken></ListMetricsResult></ListMetricsResponse>")
            } else {
                xml("<ListMetricsResponse><ListMetricsResult><Metrics>${metrics("acme.small", "acme.&amp;co")}</Metrics></ListMetricsResult></ListMetricsResponse>")
            }
            else -> xml(
                "<GetMetricStatisticsResponse><GetMetricStatisticsResult><Datapoints>" +
                    "<member><Sum>${if (form["MetricName"] == "In") 1000.0 else 5.0}</Sum><Unit>Count</Unit></member>" +
                    "<member><Sum>1.5</Sum><Unit>Count</Unit></member>" +
                    "</Datapoints></GetMetricStatisticsResult></GetMetricStatisticsResponse>",
            )
        }
    }

    @Test
    fun `should sum each metric for every dimension value the namespace has, across every page`() = runTest {
        val client = AWSClients.cloudWatch(cloudWatch, "/nowhere", keys::get) { now }

        val sums = client.sums("Acme/Models", "ModelId", listOf("In", "Out"), "us-west-2", null, now - 3600, now)

        assertEquals(
            mapOf(
                "acme.&co" to mapOf("In" to 1001.5, "Out" to 6.5),
                "acme.big" to mapOf("In" to 1001.5, "Out" to 6.5),
                "acme.small" to mapOf("In" to 1001.5, "Out" to 6.5),
            ),
            sums,
        )
    }

    @Test
    fun `should ask the region's endpoint for one period over the whole day so far, signed with the person's key`() = runTest {
        val client = AWSClients.cloudWatch(cloudWatch, "/nowhere", keys::get) { now }

        client.sums("Acme/Models", "ModelId", listOf("In"), "eu-central-1", null, now - 3601, now)

        val statistics = cloudWatch.sent.last()
        val form = statistics.body!!.decodeToString().split('&').associate { it.substringBefore('=') to it.substringAfter('=').decodeURLQueryComponent() }
        assertEquals("https://monitoring.eu-central-1.amazonaws.com/", statistics.url)
        assertEquals("3660", form["Period"])
        assertEquals("Sum", form["Statistics.member.1"])
        assertEquals("ModelId", form["Dimensions.member.1.Name"])
        assertEquals("2026-01-01T12:00:00.000Z", form["EndTime"])
        assertTrue(statistics.headers["Authorization"]!!.startsWith("AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20260101/eu-central-1/monitoring/aws4_request"))
    }

    @Test
    fun `should fail with the cloud's own words when it refuses`() = runTest {
        val refusing = Endpoint { _, _ ->
            Response(403, body = "<ErrorResponse><Error><Type>Sender</Type><Code>AccessDenied</Code><Message>not allowed</Message></Error></ErrorResponse>".encodeToByteArray())
        }
        val client = AWSClients.cloudWatch(refusing, "/nowhere", keys::get) { now }

        val error = try {
            client.sums("N", "D", listOf("M"), "us-east-1", null, now - 60, now)
            null
        } catch (error: AWSServiceError) {
            error
        }

        assertEquals("AccessDenied: not allowed", error?.message)
    }

    private fun product(dimensions: List<Triple<String, String, String>>) = buildJsonObject {
        put("terms", buildJsonObject {
            put("OnDemand", buildJsonObject {
                put("TERM1", buildJsonObject {
                    put("priceDimensions", buildJsonObject {
                        dimensions.forEachIndexed { index, (description, unit, usd) ->
                            put("D$index", buildJsonObject {
                                put("description", description)
                                put("unit", unit)
                                put("pricePerUnit", buildJsonObject { put("USD", usd) })
                            })
                        }
                    })
                })
            })
        })
    }.toString()

    @Test
    fun `should price a model per million tokens whatever unit the price list uses`() = runTest {
        val pricing = Endpoint { call, _ ->
            val filters = Json.parseToJsonElement(call.body!!.decodeToString()).jsonObject["Filters"].toString()
            val list = if ("acme.k" in filters) {
                product(listOf(Triple("Input tokens", "1K tokens", "0.0030000000"), Triple("Output tokens", "1K tokens", "0.015")))
            } else {
                product(listOf(Triple("input", "tokens", "0.0000008"), Triple("output", "Million tokens", "4.00")))
            }
            Response(200, body = buildJsonObject { put("PriceList", buildJsonArray { add(JsonPrimitive(list)) }) }.toString().encodeToByteArray())
        }
        val catalog = AWSClients.priceCatalog(pricing, "/nowhere", keys::get) { now }

        val prices = catalog.prices("AmazonBedrock", listOf("acme.k-model-20250101-v1:0", "us.acme.t"))

        assertEquals(mapOf("input" to "3", "output" to "15", "per" to "1000000", "name" to "K Model", "vendor" to "Acme"), prices["acme.k-model-20250101-v1:0"])
        assertEquals("0.8", prices["us.acme.t"]?.get("input"))
        assertEquals("4", prices["us.acme.t"]?.get("output"))
        assertEquals("AWSPriceListService.GetProducts", pricing.sent.first().headers["X-Amz-Target"])
        assertEquals("https://api.pricing.us-east-1.amazonaws.com/", pricing.sent.first().url)
    }

    @Test
    fun `should use the bundled prices when the price list can't answer, and no cost for a model it doesn't know`() = runTest {
        val down = Endpoint { _, _ -> Response(500, body = """{"__type":"InternalErrorException","message":"down"}""".encodeToByteArray()) }
        val catalog = AWSClients.priceCatalog(down, "/nowhere", keys::get) { now }

        val prices = catalog.prices("AmazonBedrock", listOf("eu.anthropic.claude-3-haiku-20240307-v1:0", "acme.new-thing-v1:0"))

        assertEquals("0.25", prices["eu.anthropic.claude-3-haiku-20240307-v1:0"]?.get("input"))
        assertEquals("Claude 3 Haiku", prices["eu.anthropic.claude-3-haiku-20240307-v1:0"]?.get("name"))
        assertEquals(mapOf("input" to "0", "output" to "0", "per" to "1000000", "name" to "New Thing", "vendor" to "Acme"), prices["acme.new-thing-v1:0"])
    }

    @Test
    fun `should ask the price list once a day for a model`() = runTest {
        var clock = now
        val pricing = Endpoint { _, _ ->
            val list = product(listOf(Triple("input", "Million tokens", "1"), Triple("output", "Million tokens", "2")))
            Response(200, body = buildJsonObject { put("PriceList", buildJsonArray { add(JsonPrimitive(list)) }) }.toString().encodeToByteArray())
        }
        val catalog = AWSClients.priceCatalog(pricing, "/nowhere", keys::get) { clock }

        catalog.prices("AmazonBedrock", listOf("acme.m"))
        catalog.prices("AmazonBedrock", listOf("acme.m"))
        clock += 86_401
        catalog.prices("AmazonBedrock", listOf("acme.m"))

        assertEquals(2, pricing.sent.size)
    }

    @Test
    fun `should keep a decimal price exact`() {
        assertEquals("3", DecimalText.normalized("3.00"))
        assertEquals("0.8", DecimalText.normalized("0.80"))
        assertEquals("3", DecimalText.shifted("0.0000030000", 6))
        assertEquals("1500", DecimalText.shifted("1.5", 3))
        assertEquals("0.000001", DecimalText.normalized("1e-6"))
        assertEquals(null, DecimalText.normalized("free"))
    }
}
