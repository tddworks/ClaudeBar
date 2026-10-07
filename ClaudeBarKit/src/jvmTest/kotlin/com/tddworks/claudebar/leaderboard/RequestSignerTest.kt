package com.tddworks.claudebar.leaderboard

import com.tddworks.claudebar.leaderboard.LeaderboardFixtures.username
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class RequestSignerTest {
    private val vectors = LeaderboardVectors.load()

    private fun key() = requireNotNull(SigningKey.of(base64URL(vectors.signing.privateKey)))

    @Test
    fun `should give the server the public key the shared vectors expect`() {
        assertEquals(vectors.signing.publicKey, key().publicKey)
    }

    @Test
    fun `should sign the method, path, time, nonce and the body's hash, as the server checks them`() {
        for (item in vectors.signing.cases) {
            val canonical = RequestSigner.canonical(item.method, item.pathAndQuery, item.timestamp, item.nonce, item.body.encodeToByteArray())
            assertEquals(item.canonical, canonical)
        }
    }

    @Test
    fun `should sign each request so the server accepts it for the member`() {
        val publicKey = base64URL(vectors.signing.publicKey)
        for (item in vectors.signing.cases) {
            val headers = RequestSigner.headers(
                member = username("tokenwhale"), key = key(), method = item.method, pathAndQuery = item.pathAndQuery,
                body = item.body.encodeToByteArray(), timestamp = item.timestamp, nonce = item.nonce,
            )

            val signature = base64URL(requireNotNull(headers["X-Signature"]))
            assertTrue(Ed25519.verify(signature, item.canonical.encodeToByteArray(), publicKey))
            assertEquals("tokenwhale", headers["X-Member"])
            assertEquals(item.timestamp.toString(), headers["X-Timestamp"])
            assertEquals(item.nonce, headers["X-Nonce"])
        }
    }

    @Test
    fun `should make the very signature the server's vectors pin, byte for byte`() {
        // Ed25519 as RFC 8032 has it is deterministic: unlike CryptoKit's, these signatures compare.
        for (item in vectors.signing.cases) {
            val headers = RequestSigner.headers(
                member = username("tokenwhale"), key = key(), method = item.method, pathAndQuery = item.pathAndQuery,
                body = item.body.encodeToByteArray(), timestamp = item.timestamp, nonce = item.nonce,
            )
            assertEquals(item.signature, headers["X-Signature"])
        }
    }

    @Test
    fun `should accept a signature the server's own vectors made`() {
        val publicKey = base64URL(vectors.signing.publicKey)
        for (item in vectors.signing.cases) {
            assertTrue(Ed25519.verify(base64URL(item.signature), item.canonical.encodeToByteArray(), publicKey))
        }
    }

    @Test
    fun `should make every nonce sixteen fresh random bytes`() {
        val first = RequestSigner.makeNonce(JvmRandomBytes)
        assertEquals(16, base64URL(first).size)
        assertNotEquals(RequestSigner.makeNonce(JvmRandomBytes), first)
    }

    @Test
    fun `should keep this Mac's key the same once it is stored and read back`() {
        val key = SigningKey.generate(JvmRandomBytes)
        assertEquals(key.publicKey, SigningKey.of(key.rawRepresentation)?.publicKey)
    }
}
