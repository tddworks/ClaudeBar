package com.tddworks.claudebar.providers

import com.tddworks.claudebar.storage.CredentialRepository
import com.tddworks.claudebar.storage.SettingsFile
import java.nio.file.Files

/** A credential store in memory. */
internal class MemoryCredentials : CredentialRepository {
    val values = mutableMapOf<String, String>()
    override fun save(value: String, key: String) { values[key] = value }
    override fun get(key: String): String? = values[key]
    override fun delete(key: String): Boolean { values.remove(key); return true }
}

/** A Keychain that refuses everything — an ad-hoc-signed build. */
internal class RefusingCredentials : CredentialRepository {
    override fun save(value: String, key: String) {}
    override fun get(key: String): String? = null
    override fun delete(key: String): Boolean = false
    override fun exists(key: String): Boolean = false
}

/** UserDefaults in memory. */
internal class MemoryLegacyStore(vararg entries: Pair<String, String>) : LegacyStore {
    val values = mutableMapOf(*entries)
    override fun string(key: String): String? = values[key]
    override fun contains(key: String): Boolean = key in values
    override fun remove(key: String) { values.remove(key) }
}

/** A settings.json of its own, in a new temporary folder. */
internal fun temporarySettingsFile(): SettingsFile =
    SettingsFile(Files.createTempDirectory("claudebar-test").resolve("settings.json").toString())
