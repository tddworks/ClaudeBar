package com.tddworks.claudebar.datasources.fetch

import com.tddworks.claudebar.datasources.HttpCall
import com.tddworks.claudebar.datasources.NetworkClient
import com.tddworks.claudebar.datasources.Response
import io.ktor.client.HttpClient
import io.ktor.client.engine.HttpClientEngine
import io.ktor.client.plugins.HttpRedirect
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.plugins.timeout
import io.ktor.client.request.request
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsBytes
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpMethod
import io.ktor.http.Url
import io.ktor.http.URLBuilder
import io.ktor.http.content.ByteArrayContent
import io.ktor.http.content.OutgoingContent
import io.ktor.http.takeFrom

/**
 * The [NetworkClient] port over a Ktor client: any status is an answer, a transport failure
 * throws. The engine is the platform's (Darwin's URLSession on macOS; a mock in tests).
 */
internal class KtorNetworkClient(private val client: HttpClient) : NetworkClient {
    override suspend fun send(call: HttpCall): Response {
        val response = client.request(call.url) {
            method = HttpMethod.parse(call.method.uppercase())
            timeout { requestTimeoutMillis = (call.timeoutSeconds * 1000).toLong() }
            // Ktor sets these two from the body itself.
            val type = call.headers.entries.firstOrNull { it.key.equals(HttpHeaders.ContentType, ignoreCase = true) }
                ?.value?.let { runCatching { ContentType.parse(it) }.getOrNull() }
            for ((name, value) in call.headers) {
                if (!name.equals(HttpHeaders.ContentType, true) && !name.equals(HttpHeaders.ContentLength, true)) {
                    headers.append(name, value)
                }
            }
            val body = call.body
            if (body != null) setBody(ByteArrayContent(body, type))
            else if (type != null) setBody(object : OutgoingContent.NoContent() { override val contentType = type })
        }
        val headers = response.headers.entries().associate { (name, values) -> name to values.joinToString(", ") }
        return Response(response.status.value, headers, response.bodyAsBytes())
    }

    companion object {
        /** A client over [engine]: redirects followed for every method, as URLSession does, unless [followRedirects] is off. */
        fun over(engine: HttpClientEngine, followRedirects: Boolean = true) = KtorNetworkClient(
            HttpClient(engine) {
                expectSuccess = false
                this.followRedirects = followRedirects
                if (followRedirects) install(HttpRedirect) { checkHttpMethod = false }
                install(HttpTimeout)
            },
        )
    }
}

/**
 * Only this Mac's own servers, which use self-signed certificates — an app's local language
 * server. Refuses any other address, and follows a redirect only to the same scheme, host
 * and port. [inner] must not follow redirects itself; its engine accepts loopback certificates.
 */
internal class LoopbackNetworkClient(
    private val inner: NetworkClient,
    private val timeoutSeconds: Double = 8.0,
) : NetworkClient {
    override suspend fun send(call: HttpCall): Response {
        var current = call.copy(timeoutSeconds = minOf(call.timeoutSeconds, timeoutSeconds))
        if (!isLoopback(current.url)) throw IllegalArgumentException("unsupported URL")
        repeat(MAX_REDIRECTS) {
            val response = inner.send(current)
            val location = response.header("Location")
            if (response.status !in REDIRECTS || location == null) return response
            val target = runCatching { URLBuilder(Url(current.url)).takeFrom(location).buildString() }.getOrNull()
            if (target == null || !isLoopback(target) || !sameOrigin(current.url, target)) return response
            val asGet = response.status == 303 || (response.status in 301..302 && current.method.uppercase() == "POST")
            current = if (asGet) current.copy(url = target, method = "GET", body = null) else current.copy(url = target)
        }
        return inner.send(current)
    }

    companion object {
        private const val MAX_REDIRECTS = 10
        private val REDIRECTS = setOf(301, 302, 303, 307, 308)

        fun isLoopback(url: String): Boolean = runCatching { Url(url) }.getOrNull()?.let {
            it.protocol.name.lowercase() in setOf("http", "https") && it.host.lowercase() in setOf("127.0.0.1", "localhost")
        } ?: false

        private fun sameOrigin(a: String, b: String): Boolean {
            val (from, to) = Url(a) to Url(b)
            return from.protocol == to.protocol && from.host.equals(to.host, true) && from.port == to.port
        }
    }
}

/** The platform's network: URLSession on macOS, shared by every fetch. */
internal expect fun systemNetworkClient(): NetworkClient

/** A [LoopbackNetworkClient] whose engine trusts any certificate 127.0.0.1 or localhost presents. */
internal expect fun insecureLocalhostNetworkClient(timeoutSeconds: Double = 8.0): NetworkClient
