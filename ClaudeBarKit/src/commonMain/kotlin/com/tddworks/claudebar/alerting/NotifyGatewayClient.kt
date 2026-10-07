package com.tddworks.claudebar.alerting

import com.tddworks.claudebar.diagnostics.AppLog
import io.ktor.client.HttpClient
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.request.header
import io.ktor.client.request.request
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpMethod
import io.ktor.http.URLBuilder
import io.ktor.http.Url
import io.ktor.http.content.TextContent
import io.ktor.http.encodeURLPathPart
import io.ktor.http.encodedPath
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlin.coroutines.cancellation.CancellationException

/**
 * Writes ClaudeBar's quota state to the Notify! gateway. The fields present in a body decide
 * how a surface draws and an absent field is left alone by the gateway's merge, so only the
 * fields ClaudeBar drives are sent — an update never stomps what the person set up elsewhere.
 *
 * - `POST /live-activity/{deviceId|activityId}?token=` — the Lock Screen tile
 * - `POST /widgets/{deviceId|widgetId}?token=` — the gauge widget
 * - `POST /screenwidgets/{deviceId|screenWidgetId}?token=` — the Home Screen widget
 * - `DELETE /live-activity/{activityId}?token=&keepFor=` — end the tile
 * - `GET /link?id=&token=` — check a pasted link
 *
 * No bearer token: the secret travels in `?token=`, so no URL is ever logged. [client]'s engine
 * is the platform's (Darwin on macOS, with its cache off — see `notifyGatewayHttpClient`).
 */
internal class NotifyGatewayClient(
    client: HttpClient,
    private val host: String = DEFAULT_HOST,
    timeoutSeconds: Double = 15.0,
) : NotifyPublishing {
    private val http = client.config {
        expectSuccess = false
        install(HttpTimeout) { requestTimeoutMillis = (timeoutSeconds * 1000).toLong() }
    }

    /**
     * Starts the tile when [activityId] is null, else updates that exact tile. A start
     * addresses the device and carries `"new": true` — a tile of ClaudeBar's own rather than
     * taking over one started elsewhere, and the override for a dismissal's sticky 410. An
     * update addresses the `LA…` id with content only: `new` there would leave two tiles.
     */
    override suspend fun publishTile(tile: NotifyTile, link: NotifyDeviceLink, activityId: String?): String {
        // The gateway refuses a Mac, a browser or a group with a 400; the link's own reason is
        // the true sentence, and names the fix.
        if (!link.supportsLiveActivity) {
            throw NotifyPublishError.LiveActivityUnavailable(
                link.kind.liveActivityUnsupportedReason
                    ?: "A Live Activity only exists on an iPhone or iPad, so use the device ID and token from the Notify! app on your phone instead.",
            )
        }
        val target: String
        val route: String
        var body = tileBody(tile)
        if (activityId != null) {
            target = activityId
            route = "POST $LIVE_ACTIVITY_ROUTE (update)"
        } else {
            target = link.deviceId
            body = JsonObject(body + ("new" to JsonPrimitive(true)))
            route = "POST $LIVE_ACTIVITY_ROUTE (start)"
            AppLog.network.debug("Notify!: starting a tile on device ${link.deviceId}")
        }
        val data = send(
            HttpMethod.Post, endpoint("$LIVE_ACTIVITY_ROUTE/$target", "token" to link.token), body, route,
            accepting = setOf(200), secret = link.token,
        )
        val decoded = decode<LiveActivityWriteResponse>(data) ?: run {
            AppLog.network.error("Notify!: $route answered a body ClaudeBar could not read")
            throw NotifyPublishError.MalformedResponse
        }
        // `pushed: false` is a success: stored, and delivered once the device reports a tile token.
        if (decoded.pushed == false) AppLog.network.debug("Notify!: tile content stored, no reachable tile token right now")
        return decoded.activityId ?: activityId ?: throw NotifyPublishError.MalformedResponse
    }

    /**
     * Creates the widget when [widgetId] is null (with `"new": true`, never hijacking the one
     * already there), else updates it. A create answers 201, or 200 when it turned out to be an update.
     */
    override suspend fun publishGauge(gauge: NotifyGauge, link: NotifyDeviceLink, widgetId: String?): String {
        // Only a group is refused — it is not a device. `InvalidPayload`, since a Live
        // Activity's remedies would send the person somewhere useless.
        if (!link.supportsWidget) {
            throw NotifyPublishError.InvalidPayload(
                link.kind.widgetUnsupportedReason
                    ?: "A group owns no Lock Screen of its own, so use the device ID and token for a single device instead.",
            )
        }
        val target: String
        val route: String
        val accepting: Set<Int>
        var body = gaugeBody(gauge)
        if (widgetId != null) {
            target = widgetId
            route = "POST $WIDGETS_ROUTE (update)"
            accepting = setOf(200)
        } else {
            target = link.deviceId
            body = JsonObject(body + ("new" to JsonPrimitive(true)))
            route = "POST $WIDGETS_ROUTE (create)"
            accepting = setOf(200, 201)
            AppLog.network.debug("Notify!: creating a widget on device ${link.deviceId}")
        }
        val data = send(
            HttpMethod.Post, endpoint("$WIDGETS_ROUTE/$target", "token" to link.token), body, route,
            accepting = accepting, secret = link.token,
        )
        val decoded = decode<WidgetWriteResponse>(data)
        return decoded?.widgetId ?: widgetId.takeIf { decoded != null } ?: run {
            AppLog.network.error("Notify!: $route answered a body ClaudeBar could not read")
            throw NotifyPublishError.MalformedResponse
        }
    }

    /**
     * Creates the Home Screen widget when [screenWidgetId] is null, else updates it. Its body
     * is the tile's, from the same [tileBody]: the gateway derives this route's contract from
     * the Live Activity's, and one tile value driving both is the point of the feature.
     */
    override suspend fun publishScreenTile(tile: NotifyTile, link: NotifyDeviceLink, screenWidgetId: String?): String {
        if (!link.supportsScreenWidget) {
            throw NotifyPublishError.InvalidPayload(
                link.kind.screenWidgetUnsupportedReason
                    ?: "A group owns no Home Screen of its own, so use the device ID and token for a single device instead.",
            )
        }
        val target: String
        val route: String
        val accepting: Set<Int>
        var body = tileBody(tile)
        if (screenWidgetId != null) {
            target = screenWidgetId
            route = "POST $SCREEN_WIDGETS_ROUTE (update)"
            accepting = setOf(200)
        } else {
            target = link.deviceId
            body = JsonObject(body + ("new" to JsonPrimitive(true)))
            route = "POST $SCREEN_WIDGETS_ROUTE (create)"
            accepting = setOf(200, 201)
            AppLog.network.debug("Notify!: creating a Home Screen widget on device ${link.deviceId}")
        }
        // Two statuses mean something different here, so they are translated where that is known.
        val data = try {
            send(
                HttpMethod.Post, endpoint("$SCREEN_WIDGETS_ROUTE/$target", "token" to link.token), body, route,
                accepting = accepting, expected = setOf(503), secret = link.token,
            )
        } catch (e: NotifyPublishError.UnexpectedStatus) {
            if (e.status != 503) throw e
            // The kill switch: nothing is wrong, so the error's own "try again later" wording.
            throw NotifyPublishError.SurfaceSwitchedOff("")
        } catch (e: NotifyPublishError.LiveActivityUnavailable) {
            // A 409 here is the device dialect finding several screen widgets, not a Live Activity problem.
            throw NotifyPublishError.InvalidPayload(e.reason)
        }
        val decoded = decode<ScreenWidgetWriteResponse>(data)
        return decoded?.screenWidgetId ?: screenWidgetId.takeIf { decoded != null } ?: run {
            AppLog.network.error("Notify!: $route answered a body ClaudeBar could not read")
            throw NotifyPublishError.MalformedResponse
        }
    }

    /** Ends the tile; a 410 counts as done — it is already gone, which is what was asked. */
    override suspend fun endTile(link: NotifyDeviceLink, activityId: String, keepForSeconds: Double) {
        send(
            HttpMethod.Delete,
            endpoint("$LIVE_ACTIVITY_ROUTE/$activityId", "token" to link.token, "keepFor" to clampedKeepFor(keepForSeconds).toString()),
            body = null, route = "DELETE $LIVE_ACTIVITY_ROUTE", accepting = setOf(200, 410), secret = link.token,
        )
    }

    /**
     * Checks an id and token pair. Rate limited to five a minute per IP, so only an explicit
     * action calls it. Its URL carries the token, so it is never answered from a cache: one
     * would keep the secret on disk, and "check right now" must not get a stale copy.
     */
    override suspend fun deviceInfo(link: NotifyDeviceLink): NotifyDeviceInfo {
        AppLog.network.debug("Notify!: checking the link for device ${link.deviceId}")
        val data = try {
            send(
                HttpMethod.Get, endpoint(LINK_ROUTE, "id" to link.deviceId, "token" to link.token), body = null,
                route = "GET $LINK_ROUTE", accepting = setOf(200), secret = link.token, uncached = true,
            )
        } catch (e: NotifyPublishError.UnexpectedStatus) {
            // This route answers 404 for a pair it doesn't know — the same problem a 403 names.
            if (e.status == 404) throw NotifyPublishError.RejectedCredentials
            throw e
        }
        val decoded = decode<LinkResponse>(data) ?: run {
            AppLog.network.error("Notify!: GET $LINK_ROUTE answered a body ClaudeBar could not read")
            throw NotifyPublishError.MalformedResponse
        }
        // The route describes groups too, which carry neither tile nor widget.
        if (decoded.type != "device") {
            throw NotifyPublishError.InvalidPayload("That link points at a Notify! group. ClaudeBar needs a device link, not a group.")
        }
        val id = decoded.id ?: throw NotifyPublishError.MalformedResponse
        val name = decoded.name ?: throw NotifyPublishError.MalformedResponse
        return NotifyDeviceInfo(deviceId = id, name = name, platform = decoded.platform)
    }

    /**
     * One request, its body back, everything that can go wrong as a [NotifyPublishError].
     * Only [route] (a label) and the status are logged — the URL carries the token, and the
     * device id appears at debug only, which never reaches the file. [expected] statuses still
     * throw but log at info: an "error" line for something normal is how a log stops being trusted.
     */
    private suspend fun send(
        method: HttpMethod,
        url: Url,
        body: JsonObject?,
        route: String,
        accepting: Set<Int>,
        expected: Set<Int> = emptySet(),
        secret: String,
        uncached: Boolean = false,
    ): String {
        val status: Int
        val data: String
        val retryAfterHeader: String?
        try {
            val response = http.request(url) {
                this.method = method
                header(HttpHeaders.Accept, "application/json")
                if (uncached) header(HttpHeaders.CacheControl, "no-store")
                if (body != null) setBody(TextContent(body.toString(), ContentType.Application.Json))
            }
            status = response.status.value
            data = response.bodyAsText()
            retryAfterHeader = response.headers[HttpHeaders.RetryAfter]
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // The kind, never the message: a transport error may quote the URL it failed on.
            AppLog.network.error("Notify!: $route could not be reached (${e::class.simpleName})")
            val reason = (e.message ?: e::class.simpleName ?: "unknown error").replace(secret, "…")
            throw NotifyPublishError.TransportFailed(reason)
        }
        AppLog.network.debug("Notify!: $route answered HTTP $status")
        if (status !in accepting) {
            val mapped = failure(status, data, retryAfterHeader)
            if (status in expected) {
                AppLog.network.info("Notify!: $route answered HTTP $status, which is expected here")
            } else {
                AppLog.network.error("Notify!: $route failed with HTTP $status")
            }
            throw mapped
        }
        return data
    }

    /** The URL, with each path segment and query value escaped — the token is opaque. */
    private fun endpoint(path: String, vararg query: Pair<String, String>): Url = URLBuilder(host).apply {
        val base = encodedPath.removeSuffix("/")
        encodedPath = base + path.split('/').joinToString("/") { it.encodeURLPathPart() }
        query.forEach { (name, value) -> parameters.append(name, value) }
    }.build()

    companion object {
        const val DEFAULT_HOST = "https://push.getnotifyapp.com"

        private const val LIVE_ACTIVITY_ROUTE = "/live-activity"
        private const val WIDGETS_ROUTE = "/widgets"
        private const val SCREEN_WIDGETS_ROUTE = "/screenwidgets"
        private const val LINK_ROUTE = "/link"

        /** The backoff ladder's first rung, for a 429 that names no wait. */
        const val DEFAULT_BACKOFF = 1800.0

        /** The gateway's ceiling on how long a finished tile may linger. */
        const val MAXIMUM_KEEP_FOR = 14400.0

        private val json = Json { ignoreUnknownKeys = true }

        private inline fun <reified T> decode(data: String): T? = runCatching { json.decodeFromString<T>(data) }.getOrNull()

        /**
         * The tile's content, stating null for what it lacks: the gateway merges, so an
         * unstated field would freeze its old value (a countdown beside a quota with no reset).
         * `status`, `endsIn`, `steps`, `step` and `button` are never mentioned, so a tile can be
         * shared with whatever else the person set up. `metrics` is body-only.
         */
        fun tileBody(tile: NotifyTile): JsonObject = JsonObject(
            mapOf(
                "title" to JsonPrimitive(tile.title),
                "body" to tile.body.json(),
                "symbol" to tile.symbolName.json(),
                "tint" to tile.tintHex.json(),
                "progress" to (tile.progress?.let(::JsonPrimitive) ?: JsonNull),
                "trailing" to tile.trailing.json(),
                "metrics" to if (tile.metrics.isEmpty()) JsonNull else JsonArray(
                    tile.metrics.map { metric ->
                        JsonObject(
                            buildMap {
                                put("label", JsonPrimitive(metric.label))
                                put("value", JsonPrimitive(metric.value))
                                metric.unit?.let { put("unit", JsonPrimitive(it)) }
                                metric.tintHex?.let { put("color", JsonPrimitive(it)) }
                            },
                        )
                    },
                ),
            ),
        )

        /**
         * The widget's content, stating null for what it lacks — a widget lives under its `WG…`
         * id until removed, so an unstated field survives forever. The title is the widget's
         * identity, which the gateway refuses to clear, so it is never null.
         */
        fun gaugeBody(gauge: NotifyGauge): JsonObject = JsonObject(
            mapOf(
                "title" to JsonPrimitive(gauge.title),
                "value" to gauge.value.json(),
                "unit" to gauge.unit.json(),
                "detail" to gauge.detail.json(),
                "symbol" to gauge.symbolName.json(),
                "tint" to gauge.tintHex.json(),
                "progress" to (gauge.progress?.let(::JsonPrimitive) ?: JsonNull),
            ),
        )

        /** 0–14400 seconds; clamped rather than letting the end call it decorates fail. */
        fun clampedKeepFor(keepForSeconds: Double): Int =
            if (!keepForSeconds.isFinite()) 0 else keepForSeconds.coerceIn(0.0, MAXIMUM_KEEP_FOR).toInt()

        /** Any answer the caller did not accept, as the matching error. */
        fun failure(status: Int, data: String, retryAfterHeader: String?): NotifyPublishError {
            val body = decode<GatewayFailure>(data)
            val message = body?.message ?: body?.error ?: ""
            return when (status) {
                400 -> NotifyPublishError.InvalidPayload(message)
                // Missing, wrong, unknown and somebody else's are one answer.
                403 -> NotifyPublishError.RejectedCredentials
                409 -> NotifyPublishError.LiveActivityUnavailable(message)
                410 -> NotifyPublishError.TileGone
                429 -> NotifyPublishError.Backoff(
                    retryAfter(body?.retryAfterSeconds, retryAfterHeader),
                    body?.openingTheAppMayHelp ?: false,
                )
                502 -> when (body?.deliveryState) {
                    // Apple never answered, so a tile may exist: keep the id and poll, never restart.
                    "unknown" -> NotifyPublishError.DeliveryUnconfirmed(body.activityId)
                    // No tile, but every unanswered start climbs a ladder to six hours: wait, don't retry.
                    "not-delivered" -> NotifyPublishError.Backoff(
                        retryAfter(body.retryAfterSeconds, retryAfterHeader),
                        body.openingTheAppMayHelp ?: false,
                    )
                    else -> NotifyPublishError.UnexpectedStatus(502)
                }
                else -> NotifyPublishError.UnexpectedStatus(status)
            }
        }

        /**
         * The body's number (from the ladder the gateway enforces), else `Retry-After`'s numeric
         * form (the date form needs a clock that agrees with the server's), else the first rung.
         */
        fun retryAfter(bodySeconds: Double?, header: String?): Double {
            if (bodySeconds != null && bodySeconds.isFinite() && bodySeconds > 0) return bodySeconds
            val headerSeconds = header?.trim()?.toDoubleOrNull()
            if (headerSeconds != null && headerSeconds.isFinite() && headerSeconds > 0) return headerSeconds
            return DEFAULT_BACKOFF
        }

        private fun String?.json() = this?.let(::JsonPrimitive) ?: JsonNull
    }
}

/** The error envelope, plus what a 429 and a 502 add to it. */
@Serializable
private class GatewayFailure(
    val error: String? = null,
    val message: String? = null,
    val retryAfterSeconds: Double? = null,
    val openingTheAppMayHelp: Boolean? = null,
    val deliveryState: String? = null,
    val activityId: String? = null,
)

/** A start names the new `LA…` id; an update echoes it and adds `pushed`. */
@Serializable
private class LiveActivityWriteResponse(val activityId: String? = null, val pushed: Boolean? = null)

/** Only the id is read: the rest echoes what ClaudeBar sent. */
@Serializable
private class WidgetWriteResponse(val widgetId: String? = null)

@Serializable
private class ScreenWidgetWriteResponse(val screenWidgetId: String? = null)

/** `GET /link`, flat snake_case; the four fields read have no underscore. */
@Serializable
private class LinkResponse(
    val type: String? = null,
    val id: String? = null,
    val name: String? = null,
    val platform: String? = null,
)
