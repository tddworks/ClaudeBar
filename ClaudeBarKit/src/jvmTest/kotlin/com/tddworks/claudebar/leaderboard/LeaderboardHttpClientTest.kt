package com.tddworks.claudebar.leaderboard

import com.tddworks.claudebar.leaderboard.LeaderboardFixtures.link
import com.tddworks.claudebar.leaderboard.LeaderboardFixtures.username
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.request.HttpRequestData
import io.ktor.http.HttpStatusCode
import io.ktor.http.content.OutgoingContent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.IOException

class LeaderboardHttpClientTest {
    private val key = SigningKey.generate(JvmRandomBytes)
    private val member = MemberCredentials(username("tokenwhale"), key)
    private val calendar = LeaderboardFixtures.calendar
    private val sent = mutableListOf<HttpRequestData>()

    /** A client whose one answer is `status` with `body`; [sent] receives the requests it made. */
    private fun client(status: Int = 200, body: String = "{}") = LeaderboardHttpClient(
        MockEngine { request ->
            sent += request
            respond(body, HttpStatusCode.fromValue(status))
        },
        calendar, JvmRandomBytes, host = HOST, now = { NOW },
    )

    private fun failing(error: Exception) =
        LeaderboardHttpClient(MockEngine { throw error }, calendar, JvmRandomBytes, host = HOST, now = { NOW })

    private val request get() = sent.single()

    private fun HttpRequestData.bodyBytes(): ByteArray = (body as? OutgoingContent.ByteArrayContent)?.bytes() ?: ByteArray(0)

    private fun HttpRequestData.json(): JsonObject = Json.parseToJsonElement(bodyBytes().decodeToString()).jsonObject

    private fun isSigned(request: HttpRequestData, by: SigningKey): Boolean {
        val query = request.url.encodedQuery
        val message = RequestSigner.canonical(
            method = request.method.value,
            pathAndQuery = request.url.encodedPath + (if (query.isEmpty()) "" else "?$query"),
            timestamp = requireNotNull(request.headers["X-Timestamp"]).toLong(),
            nonce = requireNotNull(request.headers["X-Nonce"]),
            body = request.bodyBytes(),
        )
        val signature = base64URL(requireNotNull(request.headers["X-Signature"]))
        return Ed25519.verify(signature, message.encodeToByteArray(), base64URL(by.publicKey))
    }

    // — Join —

    @Test
    fun `should ask to join with the name and public key, unsigned`() = runTest {
        client(status = 201).join("tokenwhale", key.publicKey)

        assertEquals("https://leaderboard.test/join", request.url.toString())
        assertEquals("POST", request.method.value)
        assertEquals(JsonObject(mapOf("username" to JsonPrimitive("tokenwhale"), "publicKey" to JsonPrimitive(key.publicKey))), request.json())
        assertNull(request.headers["X-Signature"])
    }

    @Test
    fun `should say the name is taken when someone already has it`() = runTest {
        val error = thrown {
            client(status = 409, body = """{"error":"usernameTaken","message":"That username is taken."}""").join("tokenwhale", key.publicKey)
        }

        assertEquals(LeaderboardError.UsernameTaken, error)
    }

    // — Upload —

    @Test
    fun `should upload the days with this Mac's date, signed over the exact body sent`() = runTest {
        val days = listOf(DailyTokens("claude", "2026-10-04", input = 1, output = 2, cacheWrite = 3, cacheRead = 4, unsplit = 0))

        client().upload(days, member)

        val body = request.json()
        assertEquals("/usage", request.url.encodedPath)
        assertEquals("PUT", request.method.value)
        assertEquals(calendar.day(NOW), body["today"]?.jsonPrimitive?.content)
        assertEquals(4L, body["days"]?.jsonArray?.first()?.jsonObject?.get("cacheRead")?.jsonPrimitive?.long)
        assertEquals("tokenwhale", request.headers["X-Member"])
        assertTrue(isSigned(request, key))
    }

    // — Reading —

    @Test
    fun `should read the member's own standing and days for the chosen view, signed`() = runTest {
        val body = """{"username":"tokenwhale","visible":false,"standing":{"rank":3,"username":"tokenwhale","total":90,"input":10,"output":20,"cache":60,"byProvider":{"claude":90}},"days":[{"provider":"claude","day":"2026-10-04","input":10,"output":20,"cacheWrite":0,"cacheRead":60,"unsplit":0}]}"""

        val summary = client(body = body).me(BoardView(BoardPeriod.SEVEN_DAYS, provider = "claude"), member)

        assertEquals("period=7d&provider=claude", request.url.encodedQuery)
        assertTrue(isSigned(request, key))
        assertFalse(summary.visible)
        assertEquals(3, summary.standing?.rank)
        assertEquals(1, summary.days.size)
    }

    @Test
    fun `should read the board fresh and unsigned`() = runTest {
        val body = """{"period":"today","provider":null,"standings":[{"rank":1,"username":"big","total":1000,"input":500,"output":0,"cache":500,"byProvider":{"claude":1000}}]}"""

        val standings = client(body = body).board(BoardView(BoardPeriod.TODAY))

        assertEquals("period=today", request.url.encodedQuery)
        assertNull(request.headers["X-Signature"])
        // Fresh: the Mac's engine is built without a cache (leaderboardHttpEngine); there is no cache here to bypass.
        assertEquals(listOf(Standing(rank = 1, username = "big", total = 1000, input = 500, cache = 500, byProvider = mapOf("claude" to 1000L))), standings)
    }

    // — Changes —

    @Test
    fun `should hide and rename the member in one signed change`() = runTest {
        client().update(MemberChange(username = "whale2", visible = false), member)

        val body = request.json()
        assertEquals("PATCH", request.method.value)
        assertEquals(JsonPrimitive("whale2"), body["username"])
        assertEquals(JsonPrimitive(false), body["visible"])
        assertNull(body["shareCountry"])
        assertTrue(isSigned(request, key))
    }

    @Test
    fun `should send only the globe opt-in when the member shares their country`() = runTest {
        client().update(MemberChange(sharesCountry = true), member)

        val body = request.json()
        assertEquals(listOf("shareCountry"), body.keys.sorted())
        assertEquals(JsonPrimitive(true), body["shareCountry"])
    }

    @Test
    fun `should send a profile link as platform and handle, and clear it when removed`() = runTest {
        client().update(MemberChange(link = MemberChange.LinkChange.Set(link(ProfileLink.Platform.GITHUB, "octocat"))), member)
        assertEquals(
            JsonObject(mapOf("platform" to JsonPrimitive("github"), "handle" to JsonPrimitive("octocat"))),
            sent.last().json()["link"],
        )

        client().update(MemberChange(link = MemberChange.LinkChange.Remove), member)
        val body = sent.last().json()
        assertEquals(listOf("link"), body.keys.sorted())
        assertEquals(JsonNull, body["link"])
    }

    @Test
    fun `should show each member's link and drop one that breaks its platform's rules`() = runTest {
        val body = """{"standings":[{"rank":1,"username":"a","total":5,"link":{"platform":"x","handle":"jack"}},{"rank":2,"username":"b","total":3,"link":{"platform":"x","handle":"https://evil.example"}},{"rank":3,"username":"c","total":1}]}"""

        val standings = client(body = body).board(BoardView(BoardPeriod.SEVEN_DAYS))

        assertEquals(listOf("jack", null, null), standings.map { it.link?.handle })
    }

    @Test
    fun `should read every country on the globe, unsigned`() = runTest {
        val body = """{"period":"30d","provider":null,"countries":[{"country":"NL","members":3,"tokens":300}],"present":["GR","VN"],"hiddenCountries":2}"""

        val globe = client(body = body).globe(BoardView(BoardPeriod.THIRTY_DAYS))

        assertEquals("/globe", request.url.encodedPath)
        assertEquals("period=30d", request.url.encodedQuery)
        assertNull(request.headers["X-Signature"])
        assertEquals(GlobeSummary(listOf(GlobeSummary.Country("NL", members = 3, tokens = 300)), present = listOf("GR", "VN")), globe)
    }

    @Test
    fun `should show only the countries with numbers when the server doesn't name the others`() = runTest {
        val body = """{"period":"30d","provider":null,"countries":[{"country":"NL","members":3,"tokens":300}],"hiddenCountries":2}"""

        val globe = client(body = body).globe(BoardView(BoardPeriod.THIRTY_DAYS))

        assertEquals(GlobeSummary(listOf(GlobeSummary.Country("NL", members = 3, tokens = 300)), present = emptyList()), globe)
    }

    @Test
    fun `should tell the member whether their country is on the globe`() = runTest {
        val body = """{"username":"tokenwhale","visible":true,"shareCountry":true,"country":"NL","standing":null,"days":[]}"""

        val summary = client(body = body).me(BoardView(BoardPeriod.SEVEN_DAYS), member)

        assertTrue(summary.sharesCountry)
        assertEquals("NL", summary.country)
    }

    @Test
    fun `should leave the leaderboard with a signed request`() = runTest {
        client().leave(member)

        assertEquals("DELETE", request.method.value)
        assertTrue(isSigned(request, key))
    }

    // — Failures —

    @Test
    fun `should say the key no longer matches when the server refuses the signature`() = runTest {
        val error = thrown { client(status = 401, body = """{"error":"unauthorized","message":"no"}""").leave(member) }

        assertEquals(LeaderboardError.Unauthorized, error)
    }

    @Test
    fun `should show the server's own words when it explains a refusal`() = runTest {
        assertEquals(
            LeaderboardError.Rejected("This Mac's clock is more than five minutes off."),
            thrown { client(status = 401, body = """{"error":"clock","message":"This Mac's clock is more than five minutes off."}""").leave(member) },
        )
        assertEquals(
            LeaderboardError.Rejected("a day can't be in the future"),
            thrown { client(status = 400, body = """{"error":"badDay","message":"a day can't be in the future"}""").upload(emptyList(), member) },
        )
    }

    @Test
    fun `should say the leaderboard is unreachable when the server fails or there is no connection`() = runTest {
        assertEquals(LeaderboardError.Unreachable, thrown { client(status = 503, body = "oops").board(BoardView(BoardPeriod.TODAY)) })
        assertEquals(LeaderboardError.Unreachable, thrown { failing(IOException("not connected")).board(BoardView(BoardPeriod.TODAY)) })
    }

    @Test
    fun `should say the leaderboard answered with something unreadable when the answer isn't a board`() = runTest {
        assertEquals(
            LeaderboardError.Rejected("The leaderboard answered with something unreadable."),
            thrown { client(body = """{"standings":[{"rank":"first"}]}""").board(BoardView(BoardPeriod.TODAY)) },
        )
    }

    private companion object {
        const val HOST = "https://leaderboard.test"
        const val NOW = 1_791_080_000.0
    }
}
