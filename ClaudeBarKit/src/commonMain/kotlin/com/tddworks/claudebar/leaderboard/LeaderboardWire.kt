package com.tddworks.claudebar.leaderboard

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.longOrNull

/**
 * The server's JSON, both ways, with the Swift app's keys. Reading is strict where Swift's
 * `Decodable` was — a missing required field or a wrong type fails the whole answer — and
 * lenient where it was: a profile link that breaks its platform's rules is dropped, never shown.
 */
internal object LeaderboardWire {
    /** Thrown inside the client when an answer can't be read. */
    class Unreadable : Exception("unreadable")

    // — Out —

    fun encode(tokens: DailyTokens) = JsonObject(
        mapOf(
            "provider" to JsonPrimitive(tokens.provider),
            "day" to JsonPrimitive(tokens.day),
            "input" to JsonPrimitive(tokens.input),
            "output" to JsonPrimitive(tokens.output),
            "cacheWrite" to JsonPrimitive(tokens.cacheWrite),
            "cacheRead" to JsonPrimitive(tokens.cacheRead),
            "unsplit" to JsonPrimitive(tokens.unsplit),
        ),
    )

    fun encode(link: ProfileLink) = JsonObject(
        mapOf("platform" to JsonPrimitive(link.platform.rawValue), "handle" to JsonPrimitive(link.handle)),
    )

    /** Fields left `null` are left out; removing the link is an explicit `"link": null`. */
    fun encode(change: MemberChange) = JsonObject(
        buildMap {
            change.username?.let { put("username", JsonPrimitive(it)) }
            change.visible?.let { put("visible", JsonPrimitive(it)) }
            change.sharesCountry?.let { put("shareCountry", JsonPrimitive(it)) }
            when (val link = change.link) {
                is MemberChange.LinkChange.Set -> put("link", encode(link.link))
                MemberChange.LinkChange.Remove -> put("link", JsonNull)
                null -> {}
            }
        },
    )

    fun upload(today: String, days: List<DailyTokens>) =
        JsonObject(mapOf("today" to JsonPrimitive(today), "days" to JsonArray(days.map(::encode))))

    fun join(username: String, publicKey: String) =
        JsonObject(mapOf("username" to JsonPrimitive(username), "publicKey" to JsonPrimitive(publicKey)))

    // — In —

    fun dailyTokens(element: JsonElement?): DailyTokens = element.fields().let {
        DailyTokens(
            provider = it.string("provider"),
            day = it.string("day"),
            input = it.long("input"),
            output = it.long("output"),
            cacheWrite = it.long("cacheWrite"),
            cacheRead = it.long("cacheRead"),
            unsplit = it.long("unsplit"),
        )
    }

    fun standing(element: JsonElement?): Standing = element.fields().let {
        Standing(
            rank = it.long("rank").toInt(),
            username = it.string("username"),
            total = it.long("total"),
            input = it.optionalLong("input") ?: 0,
            output = it.optionalLong("output") ?: 0,
            cache = it.optionalLong("cache") ?: 0,
            byProvider = it.present("byProvider")?.fields()?.mapValues { (_, value) -> value.asLong() } ?: emptyMap(),
            link = link(it["link"]),
        )
    }

    fun standings(element: JsonElement?): List<Standing> = element.fields().list("standings").map(::standing)

    fun memberSummary(element: JsonElement?): MemberSummary = element.fields().let {
        MemberSummary(
            standing = it.present("standing")?.let(::standing),
            days = it.list("days").map(::dailyTokens),
            visible = it.boolean("visible"),
            sharesCountry = it.present("shareCountry")?.asBoolean() ?: false,
            country = it.present("country")?.asString(),
            link = link(it["link"]),
        )
    }

    fun globe(element: JsonElement?): GlobeSummary = element.fields().let { globe ->
        GlobeSummary(
            countries = globe.list("countries").map { country ->
                country.fields().let { GlobeSummary.Country(it.string("country"), it.long("members"), it.long("tokens")) }
            },
            // A server from before named countries sends none.
            present = globe.present("present")?.asList()?.map { it.asString() } ?: emptyList(),
        )
    }

    /** The server's own explanation of a refusal: `{"error": …, "message": …}`. */
    fun failure(element: JsonElement?): Pair<String, String>? = runCatching {
        element.fields().let { it.string("error") to it.string("message") }
    }.getOrNull()

    private fun link(element: JsonElement?): ProfileLink? = runCatching {
        val fields = element.takeUnless { it == null || it is JsonNull }?.fields() ?: return null
        ProfileLink.Platform.of(fields.string("platform"))?.let { ProfileLink.of(it, fields.string("handle")) }
    }.getOrNull()

    // — Strict readers —

    private fun JsonElement?.fields(): JsonObject = this as? JsonObject ?: throw Unreadable()

    private fun JsonObject.present(key: String): JsonElement? = get(key)?.takeUnless { it is JsonNull }

    private fun JsonObject.required(key: String): JsonElement = present(key) ?: throw Unreadable()

    private fun JsonObject.string(key: String) = required(key).asString()

    private fun JsonObject.long(key: String) = required(key).asLong()

    private fun JsonObject.optionalLong(key: String) = present(key)?.asLong()

    private fun JsonObject.boolean(key: String) = required(key).asBoolean()

    private fun JsonObject.list(key: String) = required(key).asList()

    private fun JsonElement.asString(): String =
        (this as? JsonPrimitive)?.takeIf { it.isString }?.content ?: throw Unreadable()

    private fun JsonElement.asLong(): Long =
        (this as? JsonPrimitive)?.takeUnless { it.isString }?.longOrNull ?: throw Unreadable()

    private fun JsonElement.asBoolean(): Boolean =
        (this as? JsonPrimitive)?.takeUnless { it.isString }?.booleanOrNull ?: throw Unreadable()

    private fun JsonElement.asList(): JsonArray = this as? JsonArray ?: throw Unreadable()
}
