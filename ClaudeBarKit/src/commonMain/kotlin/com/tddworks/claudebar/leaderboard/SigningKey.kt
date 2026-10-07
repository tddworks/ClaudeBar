package com.tddworks.claudebar.leaderboard

import kotlin.io.encoding.Base64

/**
 * The key made on join. Its private half never leaves this Mac and is never logged; the server
 * holds only [publicKey], which can check a signature but never make one.
 */
internal class SigningKey private constructor(private val seed: ByteArray) {
    /** The private half, for the key store only: the 32-byte seed, as CryptoKit keeps it. */
    val rawRepresentation: ByteArray get() = seed.copyOf()

    /** The public half, base64url without padding — what `POST /join` sends. */
    val publicKey: String = Ed25519.publicKey(seed).base64URLEncoded()

    fun signature(message: ByteArray): ByteArray = Ed25519.sign(message, seed)

    override fun toString() = "SigningKey($publicKey)"

    companion object {
        fun generate(random: RandomBytes): SigningKey = SigningKey(random.bytes(Ed25519.SEED_SIZE))

        /** A key read back from the store, or null when the bytes aren't one. */
        fun of(rawRepresentation: ByteArray): SigningKey? =
            rawRepresentation.takeIf { it.size == Ed25519.SEED_SIZE }?.let { SigningKey(it.copyOf()) }
    }
}

/** Where this Mac keeps the private half of its key. */
internal interface SigningKeyStore {
    fun load(): ByteArray?
    fun save(rawKey: ByteArray)
    fun delete()
}

/** Bytes from the system's secure random source — keys and nonces. */
internal fun interface RandomBytes {
    fun bytes(count: Int): ByteArray
}

private val base64Url = Base64.UrlSafe.withPadding(Base64.PaddingOption.ABSENT)

internal fun ByteArray.base64URLEncoded(): String = base64Url.encode(this)
