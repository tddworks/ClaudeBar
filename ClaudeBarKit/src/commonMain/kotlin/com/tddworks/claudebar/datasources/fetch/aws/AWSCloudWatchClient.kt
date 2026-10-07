package com.tddworks.claudebar.datasources.fetch.aws

import com.tddworks.claudebar.datasources.CloudWatchClient
import com.tddworks.claudebar.datasources.HttpCall
import com.tddworks.claudebar.datasources.NetworkClient
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.diagnostics.AppLog
import com.tddworks.claudebar.diagnostics.isoTimestamp

/** An AWS service's refusal: its error code and message, never a credential. */
internal class AWSServiceError(val status: Int, val code: String?, message: String?) :
    Exception(listOfNotNull(code, message).joinToString(": ").ifEmpty { "AWS error $status" })

/** Signs a request with the person's credentials and sends it to an AWS endpoint. */
internal class AWSCaller(
    private val network: NetworkClient,
    private val credentials: AWSCredentialResolver,
    private val now: () -> Double,
) {
    suspend fun send(
        host: String,
        region: String,
        service: String,
        profile: String?,
        headers: List<Pair<String, String>>,
        body: ByteArray,
        timeoutSeconds: Double = 30.0,
    ): Response {
        val identity = credentials.resolve(profile)
        val signature = SignatureV4.sign(SigningRequest("POST", host, "/", emptyList(), headers, body), identity, region, service, now())
        return network.send(HttpCall("https://$host/", "POST", (headers + signature.headers).toMap(), body, timeoutSeconds))
    }

    companion object {
        /** `monitoring.us-east-1.amazonaws.com`; China's regions have their own domain. */
        fun host(prefix: String, region: String) =
            "$prefix.$region.amazonaws.com" + if (region.startsWith("cn-")) ".cn" else ""
    }
}

/**
 * CloudWatch over its Query API: every value of [dimension] that `ListMetrics` finds in the
 * namespace, then each metric's `Sum` from `GetMetricStatistics` over the whole range in one
 * period — what the AWS SDK's calls answered before.
 */
internal class AWSCloudWatchClient(private val caller: AWSCaller) : CloudWatchClient {
    override suspend fun sums(
        namespace: String,
        dimension: String,
        metrics: List<String>,
        region: String,
        profile: String?,
        fromSeconds: Double,
        toSeconds: Double,
    ): Map<String, Map<String, Double>> {
        val values = mutableSetOf<String>()
        var nextToken: String? = null
        do {
            val xml = query(region, profile, listOfNotNull("Action" to "ListMetrics", "Namespace" to namespace, nextToken?.let { "NextToken" to it }))
            for (dimensions in QueryXml.blocks(xml, "Dimensions")) {
                for (member in QueryXml.blocks(dimensions, "member")) {
                    if (QueryXml.text(member, "Name") == dimension) QueryXml.text(member, "Value")?.let(values::add)
                }
            }
            nextToken = QueryXml.text(xml, "NextToken")?.takeIf { it.isNotEmpty() }
        } while (nextToken != null)

        // One data point for the whole range; CloudWatch wants a multiple of 60.
        val period = maxOf(60, (((toSeconds - fromSeconds).toLong() + 59) / 60) * 60)
        val sums = mutableMapOf<String, Map<String, Double>>()
        for (value in values.sorted()) {
            sums[value] = metrics.associateWith { metric ->
                val xml = query(
                    region, profile,
                    listOf(
                        "Action" to "GetMetricStatistics",
                        "Namespace" to namespace,
                        "MetricName" to metric,
                        "Dimensions.member.1.Name" to dimension,
                        "Dimensions.member.1.Value" to value,
                        "StartTime" to isoTimestamp((fromSeconds * 1000).toLong()),
                        "EndTime" to isoTimestamp((toSeconds * 1000).toLong()),
                        "Period" to period.toString(),
                        "Statistics.member.1" to "Sum",
                    ),
                )
                QueryXml.texts(xml, "Sum").sumOf { it.toDoubleOrNull() ?: 0.0 }
            }
        }
        AppLog.probes.debug("$namespace in $region: ${sums.size} $dimension values")
        return sums
    }

    private suspend fun query(region: String, profile: String?, parameters: List<Pair<String, String>>): String {
        val form = (parameters + ("Version" to VERSION))
            .joinToString("&") { "${SignatureV4.encode(it.first)}=${SignatureV4.encode(it.second)}" }
        val response = caller.send(
            AWSCaller.host("monitoring", region), region, "monitoring", profile,
            listOf("Content-Type" to "application/x-www-form-urlencoded"), form.encodeToByteArray(),
        )
        val status = response.status ?: 0
        if (status !in 200..299) {
            throw AWSServiceError(status, QueryXml.text(response.text, "Code"), QueryXml.text(response.text, "Message"))
        }
        return response.text
    }

    private companion object {
        const val VERSION = "2010-08-01"
    }
}

/** Just enough XML for the Query API's flat answers: an element's text, or its blocks. */
internal object QueryXml {
    fun blocks(xml: String, tag: String): List<String> =
        Regex("<$tag>(.*?)</$tag>", RegexOption.DOT_MATCHES_ALL).findAll(xml).map { it.groupValues[1] }.toList()

    fun texts(xml: String, tag: String): List<String> = blocks(xml, tag).map(::unescaped)

    fun text(xml: String, tag: String): String? = texts(xml, tag).firstOrNull()

    private fun unescaped(text: String) = text.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"")
        .replace("&apos;", "'").replace("&#xD;", "\r").replace("&#xA;", "\n").replace("&amp;", "&")
}
