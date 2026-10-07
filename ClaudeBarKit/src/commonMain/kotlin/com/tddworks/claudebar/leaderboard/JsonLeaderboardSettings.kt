package com.tddworks.claudebar.leaderboard

import com.tddworks.claudebar.storage.SettingsFile
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.JsonUnquotedLiteral
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull

/**
 * The leaderboard's own namespace in `settings.json`, `leaderboard.*`, beside `notify.*`, with
 * the keys and encodings the Swift app wrote: `lastUpload` is Unix seconds. The private key is
 * not here: it lives in [CredentialSigningKeyStore].
 */
internal class JsonLeaderboardSettings(private val file: SettingsFile) : LeaderboardSettingsRepository {
    override fun leaderboardRecord(): LeaderboardRecord? {
        val username = file.string("leaderboard.username") ?: return null
        val link = file.string("leaderboard.linkPlatform")?.let(ProfileLink.Platform::of)
            ?.let { platform -> file.string("leaderboard.linkHandle")?.let { ProfileLink.of(platform, it) } }
        return LeaderboardRecord(
            username = username,
            sharing = strings(file.read("leaderboard.sharing")) ?: emptyList(),
            visible = boolean("leaderboard.visible") ?: true,
            lastUploadSeconds = number(file.read("leaderboard.lastUpload")),
            sharesCountry = boolean("leaderboard.sharesCountry") ?: false,
            globeHintDismissed = boolean("leaderboard.globeHintDismissed") ?: false,
            link = link,
        )
    }

    override fun isLeaderboardOn(): Boolean = boolean("leaderboard.on") ?: true

    override fun setLeaderboardOn(on: Boolean) = file.write("leaderboard.on", JsonPrimitive(on))

    override fun saveLeaderboardRecord(record: LeaderboardRecord?) {
        file.write("leaderboard.username", record?.username?.let(::JsonPrimitive))
        file.write("leaderboard.sharing", record?.sharing?.let { names -> JsonArray(names.map(::JsonPrimitive)) })
        file.write("leaderboard.visible", record?.visible?.let(::JsonPrimitive))
        file.write("leaderboard.lastUpload", record?.lastUploadSeconds?.let(::plainNumber))
        file.write("leaderboard.sharesCountry", record?.sharesCountry?.let(::JsonPrimitive))
        file.write("leaderboard.globeHintDismissed", record?.globeHintDismissed?.let(::JsonPrimitive))
        file.write("leaderboard.linkPlatform", record?.link?.platform?.rawValue?.let(::JsonPrimitive))
        file.write("leaderboard.linkHandle", record?.link?.handle?.let(::JsonPrimitive))
    }

    private fun boolean(key: String): Boolean? = (file.read(key) as? JsonPrimitive)?.takeUnless { it.isString }?.booleanOrNull

    private fun number(element: JsonElement?): Double? = (element as? JsonPrimitive)?.takeUnless { it.isString }?.doubleOrNull

    // Like Swift's `as? [String]`: one name that isn't a string, and the list doesn't read.
    private fun strings(element: JsonElement?): List<String>? = (element as? JsonArray)?.map {
        (it as? JsonPrimitive)?.takeIf { name -> name.isString }?.content ?: return null
    }

    /** A time the way Foundation writes it, `1791080000.5`, never Kotlin's `1.7910800005E9`. */
    @OptIn(ExperimentalSerializationApi::class)
    private fun plainNumber(value: Double): JsonElement {
        if (!value.isFinite()) return JsonPrimitive(value)
        if (value == kotlin.math.floor(value) && kotlin.math.abs(value) < 1e15) return JsonPrimitive(value.toLong())
        val text = value.toString()
        val exponentAt = text.indexOfFirst { it == 'E' || it == 'e' }
        if (exponentAt < 0) return JsonPrimitive(value)
        val negative = text.startsWith("-")
        val mantissa = text.substring(if (negative) 1 else 0, exponentAt)
        val exponent = text.substring(exponentAt + 1).toInt()
        val digits = mantissa.replace(".", "")
        val point = mantissa.indexOf('.').let { if (it < 0) mantissa.length else it } + exponent
        val plain = when {
            point <= 0 -> "0." + "0".repeat(-point) + digits
            point >= digits.length -> digits + "0".repeat(point - digits.length)
            else -> digits.substring(0, point) + "." + digits.substring(point)
        }
        return JsonUnquotedLiteral((if (negative) "-" else "") + plain)
    }
}
