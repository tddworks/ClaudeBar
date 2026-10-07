package com.tddworks.claudebar.leaderboard

import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.CsvSource
import org.junit.jupiter.api.Test

/** RFC 8032 §7.1, tests 1–3: the seed, its public key, a message and its one signature. */
class Ed25519Test {
    private fun hex(text: String) = text.chunked(2).map { it.toInt(16).toByte() }.toByteArray()

    @ParameterizedTest
    @CsvSource(
        "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60, d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a, '', " +
            "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b",
        "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb, 3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c, 72, " +
            "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00",
        "c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7, fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025, af82, " +
            "6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a",
    )
    fun `should make the public key and the signature the RFC gives`(seed: String, publicKey: String, message: String?, signature: String) {
        val bytes = hex(message.orEmpty())

        assertArrayEquals(hex(publicKey), Ed25519.publicKey(hex(seed)))
        assertArrayEquals(hex(signature), Ed25519.sign(bytes, hex(seed)))
        assertTrue(Ed25519.verify(hex(signature), bytes, hex(publicKey)))
    }

    @Test
    fun `should refuse a signature over another message or from another key`() {
        val seed = JvmRandomBytes.bytes(32)
        val signature = Ed25519.sign("PUT\n/usage".encodeToByteArray(), seed)

        assertTrue(Ed25519.verify(signature, "PUT\n/usage".encodeToByteArray(), Ed25519.publicKey(seed)))
        assertFalse(Ed25519.verify(signature, "PUT\n/usagE".encodeToByteArray(), Ed25519.publicKey(seed)))
        assertFalse(Ed25519.verify(signature, "PUT\n/usage".encodeToByteArray(), Ed25519.publicKey(JvmRandomBytes.bytes(32))))
    }
}
