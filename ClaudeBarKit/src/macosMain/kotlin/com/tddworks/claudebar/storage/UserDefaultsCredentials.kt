package com.tddworks.claudebar.storage

import platform.Foundation.NSUserDefaults

/**
 * Credentials in UserDefaults, under the prefix earlier releases used — the fallback for a
 * secret the Keychain refuses (an ad-hoc-signed local build). Plaintext, so never the first choice.
 */
internal class UserDefaultsCredentials(
    private val defaults: NSUserDefaults = NSUserDefaults.standardUserDefaults,
    private val keyPrefix: String = "com.claudebar.credentials.",
) : CredentialRepository {
    override fun save(value: String, key: String) = defaults.setObject(value, keyPrefix + key)

    override fun get(key: String): String? = defaults.stringForKey(keyPrefix + key)

    override fun delete(key: String): Boolean {
        defaults.removeObjectForKey(keyPrefix + key)
        return defaults.objectForKey(keyPrefix + key) == null
    }

    override fun exists(key: String): Boolean = defaults.objectForKey(keyPrefix + key) != null
}
