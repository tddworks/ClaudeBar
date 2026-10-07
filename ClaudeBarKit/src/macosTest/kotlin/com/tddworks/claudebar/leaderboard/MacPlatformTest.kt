package com.tddworks.claudebar.leaderboard

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** The Mac's random source and time zone, and the pure-Kotlin signing as Kotlin/Native compiles it. */
class MacPlatformTest {
    private fun hex(text: String) = text.chunked(2).map { it.toInt(16).toByte() }.toByteArray()

    @Test
    fun `should draw fresh random bytes from the system`() {
        val random = SystemRandomBytes()
        val first = random.bytes(32)

        assertEquals(32, first.size)
        assertFalse(first.contentEquals(random.bytes(32)))
    }

    @Test
    fun `should date a day by the Mac's own clock`() {
        val calendar = MemberCalendar(SystemUtcOffset())
        val start = calendar.startOfDay(1_791_080_000.0)

        assertEquals(calendar.day(1_791_080_000.0), calendar.day(start))
        assertTrue(1_791_080_000.0 - start in 0.0..90_000.0)
    }

    @Test
    fun `should sign as RFC 8032 has it on the Mac too`() {
        val seed = hex("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")

        assertContentEquals(hex("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"), Ed25519.publicKey(seed))
        assertContentEquals(
            hex("e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"),
            Ed25519.sign(ByteArray(0), seed),
        )
    }

    @Test
    fun `should keep a generated key the same once it is stored and read back`() {
        val key = SigningKey.generate(SystemRandomBytes())

        assertEquals(key.publicKey, SigningKey.of(key.rawRepresentation)?.publicKey)
    }
}
