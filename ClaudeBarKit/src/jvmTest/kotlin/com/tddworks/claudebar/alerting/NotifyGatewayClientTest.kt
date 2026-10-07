package com.tddworks.claudebar.alerting

import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.request.HttpRequestData
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpMethod
import io.ktor.http.HttpStatusCode
import io.ktor.http.content.TextContent
import io.ktor.http.headersOf
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.IOException

internal class NotifyGatewayClientTest {

    // Fixtures

    private val deviceId = "ABC12345"
    private val token = "sekret-token-42"
    private val activityId = "LA7Q2ZKM"
    private val widgetId = "WG4H2QZ1"
    private val screenWidgetId = "SW8N3PQ2"

    // The three ids with no Lock Screen of their own: a push-capable Mac, a web-push browser, a group.
    private val macDeviceId = "MC3F7Q2ZKM4H2QZ1"
    private val webDeviceId = "WB9K4TR2ZQ7M1XPD"
    private val groupDeviceId = "GRPA1B2C"

    private val startResponse = """
        { "success": true, "activityId": "LA7Q2ZKM", "expiresAt": "2026-09-03T18:00:00Z" }
    """.trimIndent()

    private val widgetResponse = """
        {
          "widgetId": "WG4H2QZ1",
          "content": { "title": "ClaudeBar" },
          "createdAt": "2026-09-03T09:00:00Z",
          "updatedAt": "2026-09-03T09:00:00Z",
          "updateUrl": "https://push.getnotifyapp.com/widgets/WG4H2QZ1"
        }
    """.trimIndent()

    /** `staleAt` rides along on every write; only the id is read. */
    private val screenWidgetResponse = """
        {
          "screenWidgetId": "SW8N3PQ2",
          "content": { "title": "ClaudeBar" },
          "staleAt": 1772539200,
          "createdAt": "2026-09-03T09:00:00Z",
          "updatedAt": "2026-09-03T09:00:00Z",
          "updateUrl": "https://push.getnotifyapp.com/screenwidgets/SW8N3PQ2"
        }
    """.trimIndent()

    private val linkResponse = """
        {
          "success": true,
          "type": "device",
          "id": "ABC12345",
          "name": "Apollo",
          "notification_url": "https://push.getnotifyapp.com/notify/ABC12345?token=sekret-token-42",
          "last_active": "2026-09-03T08:59:00Z",
          "platform": "iOS",
          "os_version": "26.0",
          "app_version": "3.1.0",
          "message": "ok"
        }
    """.trimIndent()

    // Domain factories: every fixture sits well inside the limits, so `!!` failing means the limits moved.

    private fun link(id: String = deviceId) = NotifyDeviceLink.of(id, token)!!

    /** Every field ClaudeBar drives, and a second metric left bare. */
    private fun tile() = NotifyTile(
        title = "ClaudeBar",
        body = "Claude 5h 42% left",
        symbolName = NotifySymbol.QUOTA,
        tintHex = "#59EBAD",
        progress = 42.0,
        trailing = "2:14",
        metrics = listOf(NotifyMetric("5h", "42", "%", "#59EBAD")!!, NotifyMetric("Week", "88")!!),
    )!!

    private fun gauge() = NotifyGauge(
        title = "ClaudeBar",
        value = "42",
        unit = "%",
        detail = "Claude 5h, resets in 2:14",
        symbolName = NotifySymbol.QUOTA,
        tintHex = "#59EBAD",
        progress = 42.0,
    )!!

    // The wire

    private class Answer(val status: Int, val body: String = "{}", val headers: Map<String, String> = emptyMap())

    private class Wire(private val answer: (HttpRequestData) -> Answer) {
        val requests = mutableListOf<HttpRequestData>()
        val last: HttpRequestData? get() = requests.lastOrNull()

        val engine = MockEngine { request ->
            requests += request
            val reply = answer(request)
            respond(
                reply.body,
                HttpStatusCode.fromValue(reply.status),
                headersOf(*reply.headers.map { (name, value) -> name to listOf(value) }.toTypedArray()),
            )
        }
    }

    private fun wire(status: Int, body: String = "{}", headers: Map<String, String> = emptyMap()) =
        Wire { Answer(status, body, headers) }

    private fun client(wire: Wire) = NotifyGatewayClient(HttpClient(wire.engine), timeoutSeconds = 1.0)

    private fun client(status: Int, body: String = "{}", headers: Map<String, String> = emptyMap()) =
        client(wire(status, body, headers))

    /** The JSON the client put on the wire. */
    private fun jsonBody(request: HttpRequestData?): JsonObject =
        Json.parseToJsonElement((request!!.body as TextContent).text).jsonObject

    private suspend fun failure(block: suspend () -> Unit): NotifyPublishError? =
        try {
            block()
            null
        } catch (e: NotifyPublishError) {
            e
        }

    // Tile start

    @Test
    fun `should start a Lock Screen tile on the linked phone with its token in the address`() = runBlocking {
        val wire = wire(200, startResponse)

        client(wire).publishTile(tile(), link(), activityId = null)

        // The device dialect, and the per-device secret in the query rather than a header.
        assertEquals("https://push.getnotifyapp.com/live-activity/ABC12345?token=sekret-token-42", wire.last?.url.toString())
        assertEquals(HttpMethod.Post, wire.last?.method)
        assertEquals("application/json", wire.last?.body?.contentType.toString())
    }

    @Test
    fun `should start a Lock Screen tile of its own showing the tile's title, line, symbol, tint, bar and countdown`() = runBlocking {
        val wire = wire(200, startResponse)

        client(wire).publishTile(tile(), link(), activityId = null)

        // `new` is what stops the start taking over a tile begun elsewhere.
        val body = jsonBody(wire.last)
        assertEquals(true, body["new"]?.jsonPrimitive?.boolean)
        assertEquals("ClaudeBar", body["title"]?.jsonPrimitive?.content)
        assertEquals("Claude 5h 42% left", body["body"]?.jsonPrimitive?.content)
        assertEquals("gauge.with.needle", body["symbol"]?.jsonPrimitive?.content)
        assertEquals("#59EBAD", body["tint"]?.jsonPrimitive?.content)
        assertEquals(42.0, body["progress"]?.jsonPrimitive?.double)
        assertEquals("2:14", body["trailing"]?.jsonPrimitive?.content)
    }

    @Test
    fun `should send each tile metric with its label, value, unit and colour, leaving out what it lacks`() = runBlocking {
        val wire = wire(200, startResponse)

        client(wire).publishTile(tile(), link(), activityId = null)

        val metrics = jsonBody(wire.last)["metrics"] as JsonArray
        assertEquals(2, metrics.size)
        val first = metrics.first().jsonObject
        assertEquals("5h", first["label"]?.jsonPrimitive?.content)
        assertEquals("42", first["value"]?.jsonPrimitive?.content)
        assertEquals("%", first["unit"]?.jsonPrimitive?.content)
        assertEquals("#59EBAD", first["color"]?.jsonPrimitive?.content)
        // The bare cell spells neither optional key, so it inherits the tile's tint.
        assertEquals(listOf("label", "value"), metrics.last().jsonObject.keys.sorted())
    }

    @Test
    fun `should remember the Lock Screen tile Notify! started`() = runBlocking {
        val identifier = client(200, startResponse).publishTile(tile(), link(), activityId = null)

        assertEquals(activityId, identifier)
    }

    // Tile update

    @Test
    fun `should update the same Lock Screen tile, never start a second one`() = runBlocking {
        val wire = wire(200, startResponse)

        client(wire).publishTile(tile(), link(), activityId = activityId)

        // `new` on an update would leave the device with two tiles.
        assertEquals("https://push.getnotifyapp.com/live-activity/LA7Q2ZKM?token=sekret-token-42", wire.last?.url.toString())
        val body = jsonBody(wire.last)
        assertFalse("new" in body)
        assertEquals("ClaudeBar", body["title"]?.jsonPrimitive?.content)
    }

    @Test
    fun `should count a tile update as done when Notify! will deliver it later`() = runBlocking {
        val client = client(200, """{ "success": true, "activityId": "LA7Q2ZKM", "pushed": false }""")

        val identifier = client.publishTile(tile(), link(), activityId = activityId)

        // Delivered when the device reports its token again: a success, not a reason to restart.
        assertEquals(activityId, identifier)
    }

    // Gauge create

    @Test
    fun `should create a widget of its own on the linked phone and remember it`() = runBlocking {
        val wire = wire(201, widgetResponse)

        val identifier = client(wire).publishGauge(gauge(), link(), widgetId = null)

        assertEquals("https://push.getnotifyapp.com/widgets/ABC12345?token=sekret-token-42", wire.last?.url.toString())
        assertEquals(HttpMethod.Post, wire.last?.method)
        val body = jsonBody(wire.last)
        assertEquals(true, body["new"]?.jsonPrimitive?.boolean)
        assertEquals("ClaudeBar", body["title"]?.jsonPrimitive?.content)
        assertEquals("42", body["value"]?.jsonPrimitive?.content)
        assertEquals("%", body["unit"]?.jsonPrimitive?.content)
        assertEquals("Claude 5h, resets in 2:14", body["detail"]?.jsonPrimitive?.content)
        assertEquals("gauge.with.needle", body["symbol"]?.jsonPrimitive?.content)
        assertEquals("#59EBAD", body["tint"]?.jsonPrimitive?.content)
        assertEquals(42.0, body["progress"]?.jsonPrimitive?.double)
        assertEquals(widgetId, identifier)
    }

    @Test
    fun `should remember the widget when Notify! answers that it updated rather than created it`() = runBlocking {
        val identifier = client(200, widgetResponse).publishGauge(gauge(), link(), widgetId = null)

        assertEquals(widgetId, identifier)
    }

    // Gauge update

    @Test
    fun `should update the same widget, never create a second one`() = runBlocking {
        val wire = wire(200, widgetResponse)

        val identifier = client(wire).publishGauge(gauge(), link(), widgetId = widgetId)

        assertEquals("https://push.getnotifyapp.com/widgets/WG4H2QZ1?token=sekret-token-42", wire.last?.url.toString())
        assertFalse("new" in jsonBody(wire.last))
        assertEquals(widgetId, identifier)
    }

    @Test
    fun `should clear every widget field ClaudeBar has no value for, keeping the title`() = runBlocking {
        val wire = wire(201, widgetResponse)
        val gauge = NotifyGauge(title = "ClaudeBar")!!

        client(wire).publishGauge(gauge, link(), widgetId = null)

        // The gateway merges, so a field left unsaid keeps whatever it held: every owned field is stated.
        val body = jsonBody(wire.last)
        assertEquals(listOf("detail", "new", "progress", "symbol", "tint", "title", "unit", "value"), body.keys.sorted())
        assertEquals(JsonNull, body["progress"])
        assertEquals(JsonNull, body["unit"])
        assertEquals(JsonNull, body["detail"])
        assertEquals(JsonNull, body["value"])
        // The title is the widget's identity, which the gateway refuses to clear.
        assertEquals(gauge.title, body["title"]?.jsonPrimitive?.content)
    }

    @Test
    fun `should clear the old countdown and bar from the Lock Screen when the quota no longer has them`() = runBlocking {
        val wire = wire(200, startResponse)
        val tile = NotifyTile(
            title = "ClaudeBar",
            body = "Credits Balance, $3.10 left",
            symbolName = NotifySymbol.QUOTA,
            tintHex = com.tddworks.claudebar.quotas.QuotaStatus.HEALTHY.notifyTintHex,
            progress = null,
            trailing = null,
            metrics = emptyList(),
        )!!

        client(wire).publishTile(tile, link(), activityId = "LA7Q2ZKM")

        val body = jsonBody(wire.last)
        assertEquals(JsonNull, body["trailing"])
        assertEquals(JsonNull, body["progress"])
        assertEquals(JsonNull, body["metrics"])
        // What ClaudeBar never drives stays unsaid.
        assertNull(body["status"])
        assertNull(body["endsIn"])
        assertNull(body["steps"])
        assertNull(body["button"])
    }

    // The Home Screen tile

    @Test
    fun `should create a Home Screen tile of its own on the linked phone and remember it`() = runBlocking {
        val wire = wire(201, screenWidgetResponse)

        val identifier = client(wire).publishScreenTile(tile(), link(), screenWidgetId = null)

        assertEquals("https://push.getnotifyapp.com/screenwidgets/ABC12345?token=sekret-token-42", wire.last?.url.toString())
        assertEquals(HttpMethod.Post, wire.last?.method)
        assertEquals("application/json", wire.last?.body?.contentType.toString())
        val body = jsonBody(wire.last)
        assertEquals(true, body["new"]?.jsonPrimitive?.boolean)
        assertEquals("ClaudeBar", body["title"]?.jsonPrimitive?.content)
        assertEquals(screenWidgetId, identifier)
    }

    @Test
    fun `should remember the Home Screen tile when Notify! answers that it updated rather than created it`() = runBlocking {
        val identifier = client(200, screenWidgetResponse).publishScreenTile(tile(), link(), screenWidgetId = null)

        assertEquals(screenWidgetId, identifier)
    }

    @Test
    fun `should update the same Home Screen tile, never create a second one`() = runBlocking {
        val wire = wire(200, screenWidgetResponse)

        val identifier = client(wire).publishScreenTile(tile(), link(), screenWidgetId = screenWidgetId)

        assertEquals("https://push.getnotifyapp.com/screenwidgets/SW8N3PQ2?token=sekret-token-42", wire.last?.url.toString())
        val body = jsonBody(wire.last)
        assertFalse("new" in body)
        assertEquals("ClaudeBar", body["title"]?.jsonPrimitive?.content)
        assertEquals(screenWidgetId, identifier)
    }

    @Test
    fun `should show the same picture of a quota on the Home Screen tile and the Lock Screen tile`() = runBlocking {
        val wire = Wire { request ->
            val isScreenWidget = "/screenwidgets/" in request.url.toString()
            Answer(if (isScreenWidget) 201 else 200, if (isScreenWidget) screenWidgetResponse else startResponse)
        }
        val client = client(wire)

        client.publishTile(tile(), link(), activityId = null)
        client.publishScreenTile(tile(), link(), screenWidgetId = null)

        // One tile value drives both surfaces, so the two bodies differ in nothing at all.
        assertEquals(2, wire.requests.size)
        val liveActivityBody = JsonObject(jsonBody(wire.requests.first()) - "new")
        val screenBody = JsonObject(jsonBody(wire.requests.last()) - "new")
        assertEquals(liveActivityBody, screenBody)
        // And a real body, not two empty ones.
        assertEquals("ClaudeBar", screenBody["title"]?.jsonPrimitive?.content)
        assertEquals(2, (screenBody["metrics"] as JsonArray).size)
    }

    // Device kind guards

    @Test
    fun `should refuse a Lock Screen tile for a Mac with the reason, sending nothing`() = runBlocking {
        // A stub that would answer 200: only the guard keeps this green.
        val wire = wire(200, startResponse)
        val reason = NotifyDeviceKind.MAC.liveActivityUnsupportedReason!!

        val error = failure { client(wire).publishTile(tile(), link(macDeviceId), activityId = null) }

        assertEquals(NotifyPublishError.LiveActivityUnavailable(reason), error)
        assertTrue(wire.requests.isEmpty())
    }

    @Test
    fun `should refuse a Lock Screen tile for a group with the reason, sending nothing`() = runBlocking {
        val wire = wire(200, startResponse)
        val reason = NotifyDeviceKind.GROUP.widgetUnsupportedReason!!

        val error = failure { client(wire).publishTile(tile(), link(groupDeviceId), activityId = null) }

        assertEquals(NotifyPublishError.LiveActivityUnavailable(reason), error)
        assertTrue(wire.requests.isEmpty())
    }

    @Test
    fun `should send a widget to a browser, since widgets are open to every device`() = runBlocking {
        val wire = wire(201, widgetResponse)

        val identifier = client(wire).publishGauge(gauge(), link(webDeviceId), widgetId = null)

        assertEquals(widgetId, identifier)
        assertTrue("/widgets/$webDeviceId" in wire.last?.url.toString())
    }

    @Test
    fun `should send a widget to a Mac too`() = runBlocking {
        val wire = wire(201, widgetResponse)

        val identifier = client(wire).publishGauge(gauge(), link(macDeviceId), widgetId = null)

        assertEquals(widgetId, identifier)
        assertNotNull(wire.last)
    }

    @Test
    fun `should refuse a widget for a group with the reason, sending nothing`() = runBlocking {
        val wire = wire(201, widgetResponse)
        val reason = NotifyDeviceKind.GROUP.widgetUnsupportedReason!!

        val error = failure { client(wire).publishGauge(gauge(), link(groupDeviceId), widgetId = null) }

        assertEquals(NotifyPublishError.InvalidPayload(reason), error)
        assertTrue(wire.requests.isEmpty())
    }

    @Test
    fun `should refuse a Home Screen tile for a group with the reason, sending nothing`() = runBlocking {
        val wire = wire(201, screenWidgetResponse)
        val reason = NotifyDeviceKind.GROUP.screenWidgetUnsupportedReason!!

        val error = failure { client(wire).publishScreenTile(tile(), link(groupDeviceId), screenWidgetId = null) }

        // Not a Live Activity problem: those remedies would send the person somewhere useless.
        assertEquals(NotifyPublishError.InvalidPayload(reason), error)
        assertTrue(wire.requests.isEmpty())
    }

    @Test
    fun `should send a Home Screen tile to a Mac, since screen widgets are open to every device`() = runBlocking {
        val wire = wire(201, screenWidgetResponse)

        val identifier = client(wire).publishScreenTile(tile(), link(macDeviceId), screenWidgetId = null)

        assertEquals(screenWidgetId, identifier)
        assertTrue("/screenwidgets/$macDeviceId" in wire.last?.url.toString())
    }

    @Test
    fun `should send a Home Screen tile to a browser too`() = runBlocking {
        val wire = wire(201, screenWidgetResponse)

        val identifier = client(wire).publishScreenTile(tile(), link(webDeviceId), screenWidgetId = null)

        assertEquals(screenWidgetId, identifier)
        assertTrue("/screenwidgets/$webDeviceId" in wire.last?.url.toString())
    }

    @Test
    fun `should still start a Lock Screen tile on an eight character app device`() = runBlocking {
        // Legacy ids can't be told from an old poll-only Mac locally, so the gateway decides.
        val wire = wire(200, startResponse)

        val identifier = client(wire).publishTile(tile(), link(), activityId = null)

        assertEquals("https://push.getnotifyapp.com/live-activity/ABC12345?token=sekret-token-42", wire.last?.url.toString())
        assertEquals(activityId, identifier)
    }

    @Test
    fun `should still create a widget on an eight character app device`() = runBlocking {
        val wire = wire(201, widgetResponse)

        val identifier = client(wire).publishGauge(gauge(), link(), widgetId = null)

        assertEquals("https://push.getnotifyapp.com/widgets/ABC12345?token=sekret-token-42", wire.last?.url.toString())
        assertEquals(widgetId, identifier)
    }

    // Ending the tile

    @Test
    fun `should end the Lock Screen tile, keeping it at most four hours`() = runBlocking {
        val wire = wire(200, """{"success": true}""")

        client(wire).endTile(link(), activityId, keepForSeconds = 99_999.0)

        // Clamped rather than rejected: the wait only decorates the end call.
        assertEquals(
            "https://push.getnotifyapp.com/live-activity/LA7Q2ZKM?token=sekret-token-42&keepFor=14400",
            wire.last?.url.toString(),
        )
        assertEquals(HttpMethod.Delete, wire.last?.method)
    }

    @Test
    fun `should end the Lock Screen tile at once when asked to keep it a negative time`() = runBlocking {
        val wire = wire(200, """{"success": true}""")

        client(wire).endTile(link(), activityId, keepForSeconds = -30.0)

        assertEquals(
            "https://push.getnotifyapp.com/live-activity/LA7Q2ZKM?token=sekret-token-42&keepFor=0",
            wire.last?.url.toString(),
        )
    }

    @Test
    fun `should count ending a tile as done when it is already gone`() = runBlocking {
        val client = client(410, """{ "error": "LiveActivityGone", "message": "already ended" }""")

        // The outcome the caller asked for, so nothing is thrown.
        assertNull(failure { client.endTile(link(), activityId, keepForSeconds = 60.0) })
    }

    // Device info

    @Test
    fun `should name the linked phone and its platform`() = runBlocking {
        val wire = wire(200, linkResponse)

        val info = client(wire).deviceInfo(link())

        // A bare read: a GET carrying content parameters would act instead.
        assertEquals("https://push.getnotifyapp.com/link?id=ABC12345&token=sekret-token-42", wire.last?.url.toString())
        assertEquals(HttpMethod.Get, wire.last?.method)
        assertEquals(0L, wire.last?.body?.contentLength ?: 0L)
        assertEquals(NotifyDeviceInfo(deviceId = "ABC12345", name = "Apollo", platform = "iOS"), info)
    }

    @Test
    fun `should say the credentials were rejected when Notify! does not know the id and token`() = runBlocking {
        // This route answers 404, not 403, alike for a wrong token and an unknown id.
        val client = client(
            404,
            """
            {
              "success": false,
              "error": "Invalid credentials",
              "code": "NOT_FOUND",
              "message": "No device or group found with the provided ID and token combination"
            }
            """.trimIndent(),
        )

        assertEquals(NotifyPublishError.RejectedCredentials, failure { client.deviceInfo(link()) })
    }

    @Test
    fun `should refuse a link that points at a group`() = runBlocking {
        val client = client(200, """{ "success": true, "type": "group", "id": "ABC12345", "name": "Family", "message": "ok" }""")

        val error = failure { client.deviceInfo(link()) }

        val reason = (error as? NotifyPublishError.InvalidPayload)?.reason
        assertEquals(true, reason?.contains("group"), "Expected InvalidPayload, got $error")
    }

    // Error mapping

    @Test
    fun `should show Notify!'s own words when it refuses what was sent`() = runBlocking {
        val client = client(400, """{ "error": "ValidationError", "message": "title must not be empty" }""")

        assertEquals(
            NotifyPublishError.InvalidPayload("title must not be empty"),
            failure { client.publishTile(tile(), link(), activityId = null) },
        )
    }

    @Test
    fun `should say the credentials were rejected when Notify! forbids the token`() = runBlocking {
        val client = client(403, """{ "error": "Forbidden", "message": "invalid token" }""")

        assertEquals(NotifyPublishError.RejectedCredentials, failure { client.publishTile(tile(), link(), activityId = null) })
    }

    @Test
    fun `should say Live Activities are unavailable, in Notify!'s words, when the phone cannot take one`() = runBlocking {
        val client = client(409, """{ "error": "LiveActivityNoCredential", "message": "Open the Notify! app once on the device." }""")

        assertEquals(
            NotifyPublishError.LiveActivityUnavailable("Open the Notify! app once on the device."),
            failure { client.publishTile(tile(), link(), activityId = null) },
        )
    }

    @Test
    fun `should show Notify!'s words, not a Live Activity problem, when a Home Screen tile is ambiguous`() = runBlocking {
        val client = client(409, """{ "error": "ScreenWidgetAmbiguous", "message": "Several screen widgets exist on this device." }""")

        assertEquals(
            NotifyPublishError.InvalidPayload("Several screen widgets exist on this device."),
            failure { client.publishScreenTile(tile(), link(), screenWidgetId = null) },
        )
    }

    @Test
    fun `should say Home Screen tiles are switched off and to try again later`() = runBlocking {
        val client = client(503, """{ "error": "ScreenWidgetsDisabled", "message": "Screen widgets are not enabled." }""")

        val error = failure { client.publishScreenTile(tile(), link(), screenWidgetId = null) }

        // Nothing is wrong, so the error's own wording; and retryable, so the driver backs off.
        assertEquals(NotifyPublishError.SurfaceSwitchedOff(""), error)
        assertTrue(error!!.message.contains("try again later"))
        assertTrue(error.isRetryable)
    }

    @Test
    fun `should say the tile is gone when the person dismissed it`() = runBlocking {
        val client = client(410, """{ "error": "LiveActivityGone", "message": "dismissed" }""")

        assertEquals(NotifyPublishError.TileGone, failure { client.publishTile(tile(), link(), activityId = activityId) })
    }

    @Test
    fun `should wait as long as Notify! says when it asks to back off`() = runBlocking {
        val client = client(
            429,
            """
            {
              "error": "LiveActivityBackoff",
              "message": "too many unanswered starts",
              "unansweredStarts": 4,
              "retryAfterSeconds": 10800,
              "openingTheAppMayHelp": true
            }
            """.trimIndent(),
        )

        assertEquals(
            NotifyPublishError.Backoff(10800.0, openingTheAppMayHelp = true),
            failure { client.publishTile(tile(), link(), activityId = null) },
        )
    }

    @Test
    fun `should wait as long as the Retry-After header says when Notify! backs off without a wait of its own`() = runBlocking {
        val client = client(
            429,
            """{ "error": "LiveActivityBackoff", "message": "too many unanswered starts" }""",
            headers = mapOf(HttpHeaders.RetryAfter to "1800"),
        )

        assertEquals(
            NotifyPublishError.Backoff(1800.0, openingTheAppMayHelp = false),
            failure { client.publishTile(tile(), link(), activityId = null) },
        )
    }

    @Test
    fun `should say delivery is unconfirmed when Notify! cannot tell whether the tile arrived`() = runBlocking {
        val client = client(
            502,
            """
            {
              "error": "LiveActivityStartFailure",
              "message": "no answer from APNs",
              "deliveryState": "unknown",
              "activityId": "LA7Q2ZKM"
            }
            """.trimIndent(),
        )

        // The id rides along so the caller can poll rather than risk a second tile.
        assertEquals(
            NotifyPublishError.DeliveryUnconfirmed(activityId),
            failure { client.publishTile(tile(), link(), activityId = null) },
        )
    }

    @Test
    fun `should wait rather than retry at once when Apple refused the start`() = runBlocking {
        val client = client(
            502,
            """
            {
              "error": "Bad Gateway",
              "message": "Apple refused the start",
              "deliveryState": "not-delivered",
              "retryAfterSeconds": 900
            }
            """.trimIndent(),
        )

        assertEquals(
            NotifyPublishError.Backoff(900.0, openingTheAppMayHelp = false),
            failure { client.publishTile(tile(), link(), activityId = null) },
        )
    }

    @Test
    fun `should check the credentials with Notify! itself, never a cached answer`() = runBlocking {
        val wire = wire(200, linkResponse)

        client(wire).deviceInfo(link())

        // The one GET, and its URL carries the token: no cache may keep the answer (macOS's
        // session also has none — notifyGatewayHttpClient).
        assertEquals("no-store", wire.last?.headers?.get(HttpHeaders.CacheControl))
    }

    @Test
    fun `should say the request failed in transit when there is no connection`() = runBlocking {
        val client = NotifyGatewayClient(HttpClient(MockEngine { throw IOException("offline") }), timeoutSeconds = 1.0)

        val error = failure { client.publishTile(tile(), link(), activityId = null) }

        // No caller ever sees the transport's own exception.
        assertTrue(error is NotifyPublishError.TransportFailed, "Expected TransportFailed, got $error")
    }

    @Test
    fun `should report the status when Notify! answers with an unexpected server error`() = runBlocking {
        assertEquals(
            NotifyPublishError.UnexpectedStatus(500),
            failure { client(500).publishTile(tile(), link(), activityId = null) },
        )
    }

    @Test
    fun `should say the answer was unreadable when Notify! succeeds with a body it cannot read`() = runBlocking {
        val client = client(200, "<html>gateway upgrade in progress</html>")

        assertEquals(NotifyPublishError.MalformedResponse, failure { client.publishTile(tile(), link(), activityId = null) })
    }
}
