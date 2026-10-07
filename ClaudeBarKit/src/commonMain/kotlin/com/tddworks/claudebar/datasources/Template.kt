package com.tddworks.claudebar.datasources

import io.ktor.http.Url
import kotlinx.serialization.json.Json
import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi

/**
 * `{{token}}`, `{{account}}`, `{{baseURL#host}}`, `{{idToken#jwt.email}}`, `{{system.now.epoch}}`
 * in a request: credential values and what the engine computes. Any name that doesn't fill
 * leaves the whole text unfilled (null), so a request never goes out half-written.
 */
internal object Template {
    fun fill(text: String, credential: Credential?, system: SystemValues? = null): String? {
        val result = StringBuilder()
        var rest = text
        while (true) {
            val open = rest.indexOf("{{").takeIf { it >= 0 } ?: break
            result.append(rest, 0, open)
            val close = rest.indexOf("}}", open + 2).takeIf { it >= 0 } ?: return null
            val name = rest.substring(open + 2, close).trim()
            result.append(value(name, credential, system) ?: return null)
            rest = rest.substring(close + 2)
        }
        return result.append(rest).toString()
    }

    private fun value(name: String, credential: Credential?, system: SystemValues?): String? = when {
        name.startsWith("system.") -> system?.value(name.removePrefix("system."))
        name.endsWith("#host") -> credential?.get(name.removeSuffix("#host"))
            ?.let { runCatching { Url(it).host }.getOrNull()?.takeIf { host -> host.isNotEmpty() } }
        else -> name.split("#jwt.").let { parts ->
            val value = credential?.get(parts[0]) ?: return null
            if (parts.size == 2) Jwt.claim(parts[1], value) else value
        }
    }
}

/** A claim from a JWT's payload — display metadata only; the token is not verified. */
internal object Jwt {
    @OptIn(ExperimentalEncodingApi::class)
    fun claim(name: String, token: String): String? {
        val parts = token.split('.')
        if (parts.size != 3) return null
        val payload = runCatching {
            Base64.UrlSafe.withPadding(Base64.PaddingOption.ABSENT_OPTIONAL).decode(parts[1]).decodeToString()
        }.getOrNull() ?: return null
        val claims = runCatching { Json.parseToJsonElement(payload) }.getOrNull() ?: return null
        return JsonPath.string(JsonPath.walk(claims, JsonPath.components(name)))
    }
}

/**
 * `{{system.x}}` — values the engine computes rather than reads, made with the fetch's own
 * [nowSeconds] (seconds since 1970) so a test can fix it. One row per value (ENGINE_DESIGN §2.9).
 */
internal class SystemValues(
    val nowSeconds: Double,
    val timeZone: String = platformTimeZone(),
    val osVersion: String = platformOsVersion(),
) {
    fun value(name: String): String? = when {
        name == "timeZone" -> timeZone
        name == "osVersion" -> osVersion
        name.startsWith("now.") -> format(name.removePrefix("now."), nowSeconds)
        name.startsWith("day") && '.' in name -> {
            val (day, format) = name.split('.', limit = 2)
            val offset = day.removePrefix("day")
            val days = if (offset.isEmpty()) 0 else if (offset[0] in "+-") offset.toIntOrNull() else null
            days?.let { format(format, (kotlin.math.floor(nowSeconds / 86_400) + it) * 86_400) }
        }
        else -> null
    }

    private fun format(name: String, seconds: Double): String? = when (name) {
        "epoch" -> seconds.toLong().toString()
        "iso8601" -> utc(seconds).let { "${it}Z" }
        "date" -> utc(seconds).substringBefore('T')
        else -> null
    }

    /** `2026-10-07T07:11:53` in UTC. */
    private fun utc(seconds: Double): String {
        val whole = kotlin.math.floor(seconds).toLong()
        return com.tddworks.claudebar.diagnostics.isoTimestamp(whole * 1000).substringBefore('.')
    }
}

internal expect fun platformTimeZone(): String
internal expect fun platformOsVersion(): String
