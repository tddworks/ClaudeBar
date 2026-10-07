package com.tddworks.claudebar.datasources.lookup

import com.tddworks.claudebar.datasources.CLICall
import com.tddworks.claudebar.datasources.CLIExecutor
import com.tddworks.claudebar.datasources.Credential
import com.tddworks.claudebar.datasources.CredentialRefreshing
import com.tddworks.claudebar.datasources.HttpCall
import com.tddworks.claudebar.datasources.JsonPath
import com.tddworks.claudebar.datasources.NetworkClient
import com.tddworks.claudebar.datasources.Template
import com.tddworks.claudebar.diagnostics.AppLog
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * OAuth 2's refresh-token grant (RFC 6749 §6): trades `refreshToken` for a new `token`, and stamps
 * `refreshedAt`. Which provider it serves is data.
 */
internal class OAuth2Refresher(
    val refresh: OAuth2Refresh,
    private val network: NetworkClient,
    /** Seconds since 1970. */
    private val now: () -> Double,
) : CredentialRefreshing {
    override val retryStatuses: List<Int> get() = refresh.onStatus
    override val writesBack: Boolean get() = true

    /** Never without a refresh token: there is nothing to trade. */
    override fun isDue(credential: Credential): Boolean {
        if (credential["refreshToken"] == null) return false
        refresh.dueWhen?.let { expiry ->
            val expiresAt = credential[expiry.expiresAt]?.let { instant(it, expiry.unit) } ?: return expiry.missingIsDue
            return now() + expiry.skew >= expiresAt
        }
        val every = refresh.every ?: return false
        val refreshedAt = credential["refreshedAt"]?.let(ISO8601Instant::parse) ?: return true
        return now() - refreshedAt > every
    }

    override suspend fun refresh(credential: Credential): Credential {
        // Nothing to trade: a key with no refresh token (a setup token, an API-key login) that is
        // refused is simply needed again.
        val refreshToken = credential["refreshToken"]?.takeIf { it.isNotEmpty() } ?: throw UsageError.AuthenticationRequired
        // The endpoint may be the credential's own issuer: `{{issuer}}/oauth2/token`.
        val url = Template.fill(refresh.tokenURL, credential)?.let(::joinedURL) ?: throw UsageError.AuthenticationRequired

        val fields = mutableListOf("grant_type" to "refresh_token", "refresh_token" to refreshToken)
        // A client the credential doesn't name is left out.
        Template.fill(refresh.clientId, credential)?.takeIf { it.isNotEmpty() }?.let { fields += "client_id" to it }
        refresh.scope?.let { fields += "scope" to it }
        val (contentType, body) = when (refresh.bodyFormat) {
            OAuth2Refresh.BodyFormat.FORM -> "application/x-www-form-urlencoded" to formBody(fields)
            OAuth2Refresh.BodyFormat.JSON -> "application/json" to
                JsonObject(fields.associate { it.first to JsonPrimitive(it.second) }).toString().encodeToByteArray()
        }

        val response = network.send(HttpCall(url, "POST", mapOf("Content-Type" to contentType), body, timeoutSeconds = 15.0))
        val status = response.status ?: throw UsageError.ExecutionFailed("Invalid response from token refresh")
        if (status == 400 || status == 401) {
            AppLog.probes.error("Token refresh refused (HTTP $status, ${errorCode(response.body) ?: "no code"})")
            throw UsageError.SessionExpired(refresh.hint)
        }
        if (status !in 200..299) throw UsageError.ExecutionFailed("Token refresh failed: HTTP $status")

        val answer = parse(response.body) as? JsonObject
        val token = answer?.text("access_token")?.takeIf { it.isNotEmpty() }
            ?: throw UsageError.ExecutionFailed("No access token in refresh response")

        var renewed = credential.with("token", token)
        // An empty refresh token in the answer never replaces the saved one.
        answer.text("refresh_token")?.takeIf { it.isNotEmpty() }?.let { renewed = renewed.with("refreshToken", it) }
        answer.text("id_token")?.let { renewed = renewed.with("idToken", it) }
        val expiry = refresh.dueWhen
        val expiresIn = JsonPath.number(answer["expires_in"])
        if (expiry != null && expiresIn != null) {
            val expiresAt = now() + expiresIn
            renewed = renewed.with(
                expiry.expiresAt,
                when (expiry.unit) {
                    OAuth2Refresh.Expiry.Unit.SECONDS -> expiresAt.toLong().toString()
                    OAuth2Refresh.Expiry.Unit.MILLISECONDS -> (expiresAt * 1000).toLong().toString()
                    OAuth2Refresh.Expiry.Unit.ISO8601 -> ISO8601Instant.format(expiresAt)
                },
            )
        }
        renewed = renewed.with("refreshedAt", ISO8601Instant.format(now()))
        AppLog.probes.info("Token refreshed")
        return renewed
    }

    companion object {
        /** An expiry in its unit, as seconds since 1970. */
        fun instant(raw: String, unit: OAuth2Refresh.Expiry.Unit): Double? = when (unit) {
            OAuth2Refresh.Expiry.Unit.SECONDS -> raw.toDoubleOrNull()
            OAuth2Refresh.Expiry.Unit.MILLISECONDS -> raw.toDoubleOrNull()?.let { it / 1000 }
            OAuth2Refresh.Expiry.Unit.ISO8601 -> ISO8601Instant.parse(raw)
        }

        /** The URL with no doubled slash where an issuer ending in `/` meets a path; null when it isn't one. */
        fun joinedURL(text: String): String? {
            if (text.any { it.isWhitespace() }) return null
            val schemeEnd = text.indexOf("://")
            val pathStart = if (schemeEnd >= 0) text.indexOf('/', schemeEnd + 3).takeIf { it >= 0 } ?: return text else 0
            val pathEnd = text.indexOfAny(charArrayOf('?', '#'), pathStart).takeIf { it >= 0 } ?: text.length
            var path = text.substring(pathStart, pathEnd)
            while ("//" in path) path = path.replace("//", "/")
            return text.substring(0, pathStart) + path + text.substring(pathEnd)
        }

        /** `name=value&…`, each value percent-encoded as a URL query allows, less `&`, `=` and `+`. */
        fun formBody(fields: List<Pair<String, String>>): ByteArray =
            fields.joinToString("&") { (name, value) -> "$name=${percentEncoded(value)}" }.encodeToByteArray()

        private const val ALLOWED = "!$'()*,-./:;?@_~"

        private fun percentEncoded(value: String): String = buildString {
            for (byte in value.encodeToByteArray()) {
                val char = (byte.toInt() and 0xFF).toChar()
                if (char in 'A'..'Z' || char in 'a'..'z' || char in '0'..'9' || char in ALLOWED) append(char)
                else append('%').append((byte.toInt() and 0xFF).toString(16).uppercase().padStart(2, '0'))
            }
        }

        /** `{"error": {"code": …}}`, `{"error": "…"}` or `{"code": …}`. */
        fun errorCode(body: ByteArray): String? {
            val answer = parse(body) as? JsonObject ?: return null
            (answer["error"] as? JsonObject)?.text("code")?.let { return it }
            answer.text("error")?.let { return it }
            return answer.text("code")
        }

        private fun parse(body: ByteArray): JsonElement? = runCatching { Json.parseToJsonElement(body.decodeToString()) }.getOrNull()

        private fun JsonObject.text(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
    }
}

/**
 * Renews a credential by running the CLI that owns it: started as a person would, it renews its
 * own login file. Only after the token was refused — never ahead of time — and the file is read
 * again, never written by us.
 */
internal class CLIRefresher(
    val call: CLICall,
    private val executor: CLIExecutor,
    /** Where a `dedicated` working directory is — ClaudeBar's own trusted folder. */
    private val dedicatedDirectory: String? = null,
) : CredentialRefreshing {
    override val retryStatuses: List<Int> get() = listOf(401)
    override val writesBack: Boolean get() = false

    override fun isDue(credential: Credential): Boolean = false

    override suspend fun refresh(credential: Credential): Credential {
        if (executor.locate(call.cli) == null) {
            AppLog.probes.info("${call.cli} isn't installed, so its login can't be renewed")
            throw UsageError.AuthenticationRequired
        }
        AppLog.probes.info("Running ${call.cli} to renew its login")
        executor.execute(
            call.cli, call.args, call.input, call.timeout,
            workingDirectory = call.workingDirectory?.let { dedicatedDirectory },
            autoResponses = call.autoResponses,
        )
        return credential
    }
}
