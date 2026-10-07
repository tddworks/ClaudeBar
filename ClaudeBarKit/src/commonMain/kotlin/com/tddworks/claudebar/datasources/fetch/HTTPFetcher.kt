package com.tddworks.claudebar.datasources.fetch

import com.tddworks.claudebar.datasources.Credential
import com.tddworks.claudebar.datasources.Fetching
import com.tddworks.claudebar.datasources.HTTPRequest
import com.tddworks.claudebar.datasources.HTTPStatusError
import com.tddworks.claudebar.datasources.HttpCall
import com.tddworks.claudebar.datasources.NetworkClient
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.datasources.SystemValues
import com.tddworks.claudebar.datasources.Template
import com.tddworks.claudebar.diagnostics.AppLog
import com.tddworks.claudebar.quotas.UsageError
import io.ktor.http.parseUrl
import kotlinx.coroutines.CancellationException

/**
 * `http` — one HTTP request. An accepted status answers with the response; anything else
 * becomes the `UsageError` a provider reports, kept with its status so a refresh-and-retry
 * can be tried. [now] is seconds since 1970.
 */
internal class HTTPFetcher(
    val request: HTTPRequest,
    private val network: NetworkClient,
    private val now: () -> Double,
) : Fetching {
    override fun isReady() = true

    override suspend fun fetch(credential: Credential?): Response {
        val system = SystemValues(now())
        val url = Template.fill(request.url, credential?.percentEncodedForURL(), system)
            ?.takeIf { parseUrl(it) != null }
            ?: throw UsageError.ExecutionFailed("Invalid URL")
        // A header whose placeholder has no value is left out, not sent half-written.
        val headers = request.headers.mapNotNull { (name, value) -> Template.fill(value, credential, system)?.let { name to it } }.toMap()
        val body = request.body?.let { Template.fill(it, credential, system) }?.encodeToByteArray()

        val response = try {
            network.send(HttpCall(url, request.method, headers, body, request.timeout))
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            AppLog.probes.error("HTTP fetch failed: ${error.message}")
            throw UsageError.ExecutionFailed("Network error: ${error.message ?: error.toString()}")
        }
        val status = response.status ?: throw UsageError.ExecutionFailed("Invalid response")

        // A 429 is always a rate limit, whatever a request accepts.
        if (status != 429 && request.accepts(status)) return response
        // The status is the fact; the definition's `errors` may word it.
        throw when (status) {
            401, 403 -> HTTPStatusError(status, UsageError.AuthenticationRequired)
            429 -> {
                val wait = retryAfter(response.header("Retry-After"), now()) ?: DEFAULT_RETRY_AFTER
                HTTPStatusError(429, UsageError.RateLimited(now() + wait))
            }
            else -> {
                AppLog.probes.error("HTTP fetch: status $status")
                HTTPStatusError(status, UsageError.ExecutionFailed("HTTP error: $status"))
            }
        }
    }

    companion object {
        const val DEFAULT_RETRY_AFTER = 5 * 60.0

        private val seconds = Regex("""^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$""")
        private val httpDate = Regex("""^[A-Za-z]{3}, (\d{1,2}) ([A-Za-z]{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) (GMT|UTC)$""")
        private val months = listOf("jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec")

        /** `Retry-After` as seconds, or as an HTTP date after [nowSeconds]. */
        fun retryAfter(value: String?, nowSeconds: Double): Double? {
            val text = value?.trim()?.takeIf { it.isNotEmpty() } ?: return null
            // `0` or a negative wait is no answer: retrying at once would hammer the endpoint.
            if (seconds.matches(text)) return text.toDouble().takeIf { it > 0 }
            val date = httpDateSeconds(text) ?: return null
            return (date - nowSeconds).takeIf { it > 0 }
        }

        /** `Tue, 14 Nov 2023 22:14:20 GMT` in seconds since 1970. */
        private fun httpDateSeconds(text: String): Double? {
            val parts = httpDate.matchEntire(text)?.groupValues ?: return null
            val month = months.indexOf(parts[2].lowercase()).takeIf { it >= 0 }?.plus(1) ?: return null
            val day = parts[1].toInt()
            val (hour, minute, second) = Triple(parts[4].toInt(), parts[5].toInt(), parts[6].toInt())
            if (day !in 1..31 || hour > 23 || minute > 59 || second > 60) return null
            return (daysFromCivil(parts[3].toLong(), month, day) * 86_400 + hour * 3600 + minute * 60 + second).toDouble()
        }

        /** Days since 1970-01-01 (Howard Hinnant's algorithm). */
        private fun daysFromCivil(year: Long, month: Int, day: Int): Long {
            val y = if (month <= 2) year - 1 else year
            val era = y.floorDiv(400L)
            val yoe = y - era * 400
            val doy = (153 * (if (month > 2) month - 3 else month + 9) + 2) / 5 + day - 1
            val doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
            return era * 146_097 + doe - 719_468
        }
    }
}

/**
 * The values as they go into a URL: `team & org` becomes `team%20%26%20org`, so a value can
 * never add a query item or end the URL. Kept: what a URL query allows, less `&=+?#`.
 */
internal fun Credential.percentEncodedForURL(): Credential = Credential(values.mapValues { percentEncodedQueryValue(it.value) })

private const val QUERY_SAFE = "-._~!$'()*,;:@/"

private fun percentEncodedQueryValue(text: String): String = buildString {
    for (byte in text.encodeToByteArray()) {
        val char = (byte.toInt() and 0xFF).toChar()
        if (char.isAsciiLetterOrDigit() || char in QUERY_SAFE) append(char)
        else append('%').append(HEX[(byte.toInt() shr 4) and 0xF]).append(HEX[byte.toInt() and 0xF])
    }
}

private const val HEX = "0123456789ABCDEF"

private fun Char.isAsciiLetterOrDigit() = this in 'a'..'z' || this in 'A'..'Z' || this in '0'..'9'
