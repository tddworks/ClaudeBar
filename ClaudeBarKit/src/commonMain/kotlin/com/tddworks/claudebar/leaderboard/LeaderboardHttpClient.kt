package com.tddworks.claudebar.leaderboard

import io.ktor.client.HttpClient
import io.ktor.client.engine.HttpClientEngine
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.request.header
import io.ktor.client.request.request
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsBytes
import io.ktor.http.ContentType
import io.ktor.http.HttpMethod
import io.ktor.http.URLBuilder
import io.ktor.http.content.ByteArrayContent
import io.ktor.http.content.OutgoingContent
import io.ktor.http.takeFrom
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlin.coroutines.cancellation.CancellationException

/**
 * The leaderboard server (`claudebar-api.tddworks.com`) over HTTPS. Signed calls are signed over
 * the exact bytes sent; the host is fixed, so a setting can't point the app's key at someone
 * else's server. The board is cacheable for the web page; the app always reads it fresh, or a
 * board fetched before your first upload would hide you for minutes — the engine is built
 * without a cache (see `leaderboardHttpEngine` on macOS).
 */
internal class LeaderboardHttpClient(
    engine: HttpClientEngine,
    private val calendar: MemberCalendar,
    private val random: RandomBytes,
    private val host: String = DEFAULT_HOST,
    timeoutSeconds: Double = 15.0,
    private val now: () -> Double,
) : LeaderboardAPI {
    private val http = HttpClient(engine) {
        expectSuccess = false
        install(HttpTimeout) { requestTimeoutMillis = (timeoutSeconds * 1000).toLong() }
    }

    override suspend fun join(username: String, publicKey: String) {
        send("POST", "/join", body = LeaderboardWire.join(username, publicKey))
    }

    override suspend fun upload(days: List<DailyTokens>, credentials: MemberCredentials) {
        send("PUT", "/usage", body = LeaderboardWire.upload(calendar.day(now()), days), signedBy = credentials)
    }

    override suspend fun me(view: BoardView, credentials: MemberCredentials): MemberSummary =
        decode(send("GET", "/me", query(view), signedBy = credentials), LeaderboardWire::memberSummary)

    override suspend fun update(change: MemberChange, credentials: MemberCredentials) {
        send("PATCH", "/me", body = LeaderboardWire.encode(change), signedBy = credentials)
    }

    override suspend fun leave(credentials: MemberCredentials) {
        send("DELETE", "/me", signedBy = credentials)
    }

    override suspend fun board(view: BoardView): List<Standing> =
        decode(send("GET", "/board", query(view)), LeaderboardWire::standings)

    override suspend fun globe(view: BoardView): GlobeSummary =
        decode(send("GET", "/globe", query(view)), LeaderboardWire::globe)

    // — Wire —

    private fun query(view: BoardView) = "period=${view.period.rawValue}" + (view.provider?.let { "&provider=$it" } ?: "")

    private suspend fun send(
        method: String,
        path: String,
        query: String? = null,
        body: JsonElement? = null,
        signedBy: MemberCredentials? = null,
    ): ByteArray {
        val pathAndQuery = path + (query?.let { "?$it" } ?: "")
        val url = runCatching { URLBuilder(host).takeFrom(pathAndQuery).build() }
            .getOrElse { throw LeaderboardError.Unreachable }
        val bytes = body?.toString()?.encodeToByteArray()
        val headers = signedBy?.let {
            RequestSigner.headers(
                member = it.username, key = it.key, method = method, pathAndQuery = pathAndQuery,
                body = bytes ?: ByteArray(0), timestamp = now().toLong(), nonce = RequestSigner.makeNonce(random),
            )
        }.orEmpty()

        val response = try {
            http.request(url) {
                this.method = HttpMethod.parse(method)
                headers.forEach { (name, value) -> header(name, value) }
                setBody(if (bytes != null) ByteArrayContent(bytes, ContentType.Application.Json) else NoBody)
            }
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            throw LeaderboardError.Unreachable
        }
        val status = response.status.value
        val data = try {
            response.bodyAsBytes()
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            throw LeaderboardError.Unreachable
        }
        if (status in 200 until 300) return data
        throw error(status, data)
    }

    private fun error(status: Int, data: ByteArray): LeaderboardError {
        val failure = LeaderboardWire.failure(runCatching { Json.parseToJsonElement(data.decodeToString()) }.getOrNull())
        return when {
            status == 409 -> LeaderboardError.UsernameTaken
            status == 401 && (failure == null || failure.first == "unauthorized") -> LeaderboardError.Unauthorized
            status in 400 until 500 -> LeaderboardError.Rejected(failure?.second ?: "The leaderboard refused that ($status).")
            else -> LeaderboardError.Unreachable
        }
    }

    private fun <T> decode(data: ByteArray, read: (JsonElement) -> T): T = try {
        read(Json.parseToJsonElement(data.decodeToString()))
    } catch (_: Exception) {
        throw LeaderboardError.Rejected("The leaderboard answered with something unreadable.")
    }

    /** No body, still declared JSON, as every request the Swift app sent was. */
    private object NoBody : OutgoingContent.NoContent() {
        override val contentType: ContentType = ContentType.Application.Json
    }

    companion object {
        const val DEFAULT_HOST = "https://claudebar-api.tddworks.com"
    }
}
