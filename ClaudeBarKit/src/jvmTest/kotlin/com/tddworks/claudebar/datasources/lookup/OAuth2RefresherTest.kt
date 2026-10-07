package com.tddworks.claudebar.datasources.lookup

import com.tddworks.claudebar.datasources.Credential
import com.tddworks.claudebar.datasources.NetworkClient
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class OAuth2RefresherTest {
    private val now = 1_700_000_000.0

    private fun answering(status: Int, body: String = "") = FakeNetwork { Response(status = status, body = body.encodeToByteArray()) }

    /** An expiry in milliseconds, refreshed five minutes early, with a JSON body. */
    private fun refresher(network: NetworkClient = FakeNetwork(), bodyFormat: OAuth2Refresh.BodyFormat = OAuth2Refresh.BodyFormat.JSON) =
        OAuth2Refresher(
            OAuth2Refresh(
                tokenURL = "https://auth.example.com/oauth/token",
                clientId = "client-1",
                onStatus = listOf(401),
                hint = "Log in again.",
                bodyFormat = bodyFormat,
                scope = "read write",
                dueWhen = OAuth2Refresh.Expiry(expiresAt = "expiresAt", unit = OAuth2Refresh.Expiry.Unit.MILLISECONDS, skew = 300.0),
            ),
            network,
        ) { now }

    private fun credential(expiresIn: Double?, refreshToken: String? = "refresh-1"): Credential {
        val values = mutableMapOf("token" to "token-1")
        refreshToken?.let { values["refreshToken"] = it }
        expiresIn?.let { values["expiresAt"] = ((now + it) * 1000).toLong().toString() }
        return Credential(values)
    }

    // isDue

    @Test
    fun `should renew a login whose token has expired`() {
        assertTrue(refresher().isDue(credential(expiresIn = -3600.0)))
    }

    @Test
    fun `should renew a login whose token expires within five minutes`() {
        // 4 minutes left, less than the 5 minute skew
        assertTrue(refresher().isDue(credential(expiresIn = 4 * 60.0)))
    }

    @Test
    fun `should not renew a login whose token has more than five minutes left`() {
        assertFalse(refresher().isDue(credential(expiresIn = 3600.0)))
    }

    @Test
    fun `should renew a login whose token has no expiry`() {
        assertTrue(refresher().isDue(credential(expiresIn = null)))
    }

    @Test
    fun `should never renew a long-lived token that has no refresh token`() {
        // A long-lived setup token: no expiry and nothing to trade.
        assertFalse(refresher().isDue(credential(expiresIn = null, refreshToken = null)))
        assertFalse(refresher().isDue(credential(expiresIn = -3600.0, refreshToken = null)))
    }

    // refresh

    @Test
    fun `should renew a login by posting its refresh token, client and scope as JSON`() = runTest {
        val network = answering(200, """{"access_token":"token-2"}""")

        refresher(network).refresh(credential(expiresIn = -60.0))

        val request = network.sent.single()
        assertEquals("POST", request.method)
        assertEquals("https://auth.example.com/oauth/token", request.url)
        assertEquals("application/json", request.headers["Content-Type"])
        assertEquals(
            JsonObject(mapOf(
                "grant_type" to JsonPrimitive("refresh_token"),
                "refresh_token" to JsonPrimitive("refresh-1"),
                "client_id" to JsonPrimitive("client-1"),
                "scope" to JsonPrimitive("read write"),
            )),
            Json.parseToJsonElement(request.body!!.decodeToString()),
        )
    }

    @Test
    fun `should renew a login by posting its refresh token, client and scope as a form when the server wants one`() = runTest {
        val network = answering(200, """{"access_token":"token-2"}""")

        refresher(network, OAuth2Refresh.BodyFormat.FORM).refresh(credential(expiresIn = -60.0))

        val request = network.sent.single()
        assertEquals("application/x-www-form-urlencoded", request.headers["Content-Type"])
        assertEquals("grant_type=refresh_token&refresh_token=refresh-1&client_id=client-1&scope=read%20write", request.body!!.decodeToString())
    }

    @Test
    fun `should keep the renewed tokens and their new expiry, so the login isn't renewed again at once`() = runTest {
        val network = answering(200, """{"access_token":"token-2","refresh_token":"refresh-2","expires_in":3600}""")

        val renewed = refresher(network).refresh(credential(expiresIn = -60.0))

        assertEquals("token-2", renewed.token)
        assertEquals("refresh-2", renewed["refreshToken"])
        assertEquals("1700003600000", renewed["expiresAt"])
        assertEquals("2023-11-14T22:13:20Z", renewed["refreshedAt"])
        assertFalse(refresher().isDue(renewed))
    }

    @Test
    fun `should keep the old refresh token when the renewal gives no new one`() = runTest {
        val renewed = refresher(answering(200, """{"access_token":"token-2"}""")).refresh(credential(expiresIn = -60.0))

        assertEquals("refresh-1", renewed["refreshToken"])
    }

    @Test
    fun `should say the session expired, with the hint, when the renewal is refused`() = runTest {
        val network = answering(400, """{ "error": "invalid_grant", "error_description": "Refresh token has been revoked" }""")

        val error = failure<UsageError> { refresher(network).refresh(credential(expiresIn = -60.0)) }

        assertEquals(UsageError.SessionExpired("Log in again."), error)
        assertEquals("Log in again.", (error as UsageError.SessionExpired).hint)
    }

    @Test
    fun `should say the renewal failed, naming the HTTP status, when the server errors`() = runTest {
        val error = failure<UsageError> { refresher(answering(503)).refresh(credential(expiresIn = -60.0)) }

        assertEquals(UsageError.ExecutionFailed("Token refresh failed: HTTP 503"), error)
    }

    @Test
    fun `should ask to sign in when a renewal is needed but the login has no refresh token`() = runTest {
        val error = failure<UsageError> { refresher().refresh(credential(expiresIn = null, refreshToken = null)) }

        assertEquals(UsageError.AuthenticationRequired, error)
    }

    // A refresh whose endpoint the credential names

    private fun issuerRefresher(network: NetworkClient, missingIsDue: Boolean = false) = OAuth2Refresher(
        OAuth2Refresh(
            tokenURL = "{{issuer}}/oauth2/token", clientId = "{{clientId}}", onStatus = listOf(401),
            hint = "Run `acme login` again.",
            dueWhen = OAuth2Refresh.Expiry("expiresAt", OAuth2Refresh.Expiry.Unit.ISO8601, skew = 300.0, missingIsDue = missingIsDue),
        ),
        network,
    ) { now }

    @Test
    fun `should renew within five minutes of a written-out expiry, and without one only when the definition says so`() {
        val expired = Credential(mapOf("token" to "t", "refreshToken" to "r", "expiresAt" to "2023-11-14T22:13:00.123456Z"))
        val later = Credential(mapOf("token" to "t", "refreshToken" to "r", "expiresAt" to "2023-11-15T22:13:20Z"))
        val none = Credential(mapOf("token" to "t", "refreshToken" to "r"))
        assertTrue(issuerRefresher(FakeNetwork()).isDue(expired))
        assertFalse(issuerRefresher(FakeNetwork()).isDue(later))
        assertFalse(issuerRefresher(FakeNetwork()).isDue(none))
        assertTrue(issuerRefresher(FakeNetwork(), missingIsDue = true).isDue(none))
    }

    @Test
    fun `should renew at the address the login names, keeping the saved refresh token when the server sends an empty one`() = runTest {
        val network = answering(200, """{"access_token":"new","refresh_token":"","expires_in":3600}""")

        val renewed = issuerRefresher(network).refresh(
            Credential(mapOf("token" to "old", "refreshToken" to "r-1", "issuer" to "https://login.acme.test/")),
        )

        val request = network.sent.single()
        assertEquals("https://login.acme.test/oauth2/token", request.url)
        assertFalse("client_id" in request.body!!.decodeToString())
        assertEquals("new", renewed.token)
        assertEquals("r-1", renewed["refreshToken"]) // an empty refresh token never replaces the saved one
        assertTrue(renewed["expiresAt"]!!.startsWith("2023-11-14T23:13:20"))
    }

    @Test
    fun `should ask to sign in when a login whose renewal address it names has no refresh token`() = runTest {
        val error = failure<UsageError> {
            issuerRefresher(FakeNetwork()).refresh(Credential(mapOf("token" to "old", "issuer" to "https://x.test")))
        }

        assertEquals(UsageError.AuthenticationRequired, error)
    }
}
