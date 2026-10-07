package com.tddworks.claudebar.leaderboard

import org.kotlincrypto.hash.sha2.SHA256

/**
 * Signs a request the way the Worker checks it: over the method, the path and query, the time,
 * a nonce and the body's SHA-256, joined by newlines. The server verifies the exact bytes it
 * received, so the body signed here must be the body sent. Pinned by
 * `ClaudeBarKit/src/jvmTest/resources/leaderboard/vectors.json`, which the server checks an identical copy of.
 */
internal object RequestSigner {
    fun canonical(method: String, pathAndQuery: String, timestamp: Long, nonce: String, body: ByteArray): String {
        val hash = SHA256().digest(body).joinToString("") { (it.toInt() and 0xff).toString(16).padStart(2, '0') }
        return listOf(method, pathAndQuery, timestamp.toString(), nonce, hash).joinToString("\n")
    }

    fun headers(
        member: Username,
        key: SigningKey,
        method: String,
        pathAndQuery: String,
        body: ByteArray,
        timestamp: Long,
        nonce: String,
    ): Map<String, String> {
        val message = canonical(method, pathAndQuery, timestamp, nonce, body)
        return mapOf(
            "X-Member" to member.value,
            "X-Timestamp" to timestamp.toString(),
            "X-Nonce" to nonce,
            "X-Signature" to key.signature(message.encodeToByteArray()).base64URLEncoded(),
        )
    }

    /** Sixteen random bytes, base64url: a signed request is accepted once. */
    fun makeNonce(random: RandomBytes): String = random.bytes(16).base64URLEncoded()
}
