package com.tddworks.claudebar.leaderboard

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File
import kotlin.io.encoding.Base64

/**
 * `ClaudeBarKit/src/jvmTest/resources/leaderboard/vectors.json`: the username rule and the signing cases. The
 * server (tddworks/claudebar-server) checks an identical copy, so the two sides can't drift
 * apart: change both together. Read from the Swift tests' folder, so there is one copy here too.
 */
@Serializable
internal data class LeaderboardVectors(val usernames: Usernames, val signing: Signing, val links: Links) {
    @Serializable
    data class Usernames(val valid: List<String>, val invalid: List<String>)

    @Serializable
    data class Signing(val privateKey: String, val publicKey: String, val cases: List<Case>) {
        @Serializable
        data class Case(
            val method: String,
            val pathAndQuery: String,
            val timestamp: Long,
            val nonce: String,
            val body: String,
            val canonical: String,
            val signature: String,
        )
    }

    @Serializable
    data class Links(val valid: List<List<String>>, val invalid: List<List<String>>)

    companion object {
        private val json = Json { ignoreUnknownKeys = true }

        fun load(): LeaderboardVectors =
            json.decodeFromString(serializer(), File("src/jvmTest/resources/leaderboard/vectors.json").readText())
    }
}

internal fun base64URL(text: String): ByteArray =
    Base64.UrlSafe.withPadding(Base64.PaddingOption.ABSENT_OPTIONAL).decode(text)
