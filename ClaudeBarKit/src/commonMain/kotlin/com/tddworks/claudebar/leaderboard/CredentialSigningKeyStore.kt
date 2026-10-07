package com.tddworks.claudebar.leaderboard

import com.tddworks.claudebar.diagnostics.AppLog
import com.tddworks.claudebar.storage.CredentialRepository
import kotlin.io.encoding.Base64

/**
 * The leaderboard key's private half, kept like Notify!'s token: the Keychain first, read back
 * to prove it landed, and the app's own credential store when the Keychain refuses a locally
 * built, ad-hoc signed app. Never `settings.json`, never logged. Base64 under
 * `leaderboard-signing-key`, as the Swift app kept it.
 */
internal class CredentialSigningKeyStore(
    private val secure: CredentialRepository,
    private val fallback: CredentialRepository,
) : SigningKeyStore {
    override fun load(): ByteArray? =
        (secure.get(KEY) ?: fallback.get(KEY))?.let { runCatching { Base64.Default.decode(it) }.getOrNull() }

    override fun save(rawKey: ByteArray) {
        val encoded = Base64.Default.encode(rawKey)
        secure.save(encoded, KEY)
        if (secure.get(KEY) == encoded) {
            fallback.delete(KEY)
            return
        }
        AppLog.credentials.warning("Leaderboard key could not be stored in the Keychain, keeping it in the app credential store instead")
        fallback.save(encoded, KEY)
    }

    override fun delete() {
        secure.delete(KEY)
        fallback.delete(KEY)
    }

    /** Whether the key is in the Keychain rather than the fallback store. */
    val isSecure: Boolean get() = secure.get(KEY) != null

    companion object {
        const val KEY = "leaderboard-signing-key"
    }
}
