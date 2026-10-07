package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.SecretVault
import com.tddworks.claudebar.storage.CredentialRepository

/**
 * The vault definitions read their keys from — ClaudeBar's credential store, under
 * `provider.<id>.<name>`. A definition names the key; the value lives only here. A default
 * login's key an older release kept elsewhere is moved here the first time it is read.
 */
internal class ProviderVault(
    private val credentials: CredentialRepository,
    /** UserDefaults, where earlier releases kept keys. Only a default login can read one. */
    private val legacyStore: LegacyStore,
) : SecretVault {
    override fun secret(name: String, provider: String): String? {
        val migration = migration(name, provider) ?: return credentials.get(key(name, provider))
        return migration.get()
    }

    override fun save(value: String, name: String, provider: String) {
        val migration = migration(name, provider)
        if (migration != null) migration.save(value) else credentials.save(value, key(name, provider))
    }

    override fun delete(name: String, provider: String): Boolean {
        val migration = migration(name, provider) ?: return credentials.delete(key(name, provider))
        return migration.delete()
    }

    // Compatibility lives at storage's boundary, never in the provider runtime. Exact
    // default-login keys only: an added login never inherits this entry.
    private fun migration(name: String, provider: String): SecureCredentialMigration? {
        val key = key(name, provider)
        val legacy = legacyKeys[key] ?: return null
        return SecureCredentialMigration(credentials, legacyStore, key, legacy.first, legacy.second)
    }

    companion object {
        fun key(name: String, provider: String) = "provider.$provider.$name"

        /**
         * Where a default login's key was kept before its provider became a definition: a
         * UserDefaults entry, and for some an older Keychain item. A migrating provider adds a
         * row here, never a branch.
         */
        private val legacyKeys: Map<String, Pair<String, String?>> = mapOf(
            "provider.deepseek.apiKey" to ("com.claudebar.credentials.deepseek-api-key" to null),
            "provider.minimax.apiKey" to ("com.claudebar.credentials.minimax-api-key" to null),
            "provider.vercel-gateway.apiKey" to ("com.claudebar.credentials.vercel-api-key" to "vercel-ai-gateway-api-key"),
            "provider.zai.apiKey" to ("com.claudebar.credentials.zai-api-key" to "zai-glm-api-key"),
            "provider.copilot.token" to ("com.claudebar.credentials.github-copilot-token" to "github-copilot-token"),
            "provider.alibaba.apiKey" to ("com.claudebar.credentials.alibaba-api-key" to null),
            "provider.alibaba.cookie" to ("com.claudebar.credentials.alibaba-manual-cookie" to null),
        )
    }
}

/**
 * Bridges a legacy UserDefaults credential to its secure replacement. Reads prefer secure
 * storage; a legacy value is copied there and removed from UserDefaults only once it is
 * verifiably stored — a Keychain that refuses an ad-hoc-signed build never loses the key.
 */
internal class SecureCredentialMigration(
    private val secureStore: CredentialRepository,
    private val legacyStore: LegacyStore,
    private val secureKey: String,
    private val legacyKey: String,
    /** The same credential already in secure storage under an older name. */
    private val legacySecureKey: String? = null,
) {
    /** Saves securely, and removes the legacy copies once it is verified. */
    fun save(value: String) {
        secureStore.save(value, secureKey)
        if (secureStore.get(secureKey) == value) {
            if (legacySecureKey != null && legacySecureKey != secureKey) secureStore.delete(legacySecureKey)
            legacyStore.remove(legacyKey)
        }
    }

    /** The secure value, or the legacy one, migrated. */
    fun get(): String? {
        secureStore.get(secureKey)?.let { return it }
        if (legacySecureKey != null) {
            secureStore.get(legacySecureKey)?.let { value ->
                save(value)
                return value
            }
        }
        val legacy = legacyStore.string(legacyKey) ?: return null
        save(legacy)
        return legacy
    }

    /** Deletes both copies once the secure one is gone; true when both are absent afterwards. */
    fun delete(): Boolean {
        if (!secureStore.delete(secureKey)) return false
        if (legacySecureKey != null && legacySecureKey != secureKey && secureStore.get(legacySecureKey) != null &&
            !secureStore.delete(legacySecureKey)
        ) return false
        legacyStore.remove(legacyKey)
        return !legacyStore.contains(legacyKey)
    }

    fun exists(): Boolean = get() != null
}
