package com.tddworks.claudebar.storage

import kotlin.native.ObjCName

/** Where a provider's secrets are kept — the Keychain, never settings.json, a log line or an export. */
// Swift sees it as KitCredentialRepository until phase 4 retires Domain's Swift protocol of the same name.
@ObjCName(swiftName = "KitCredentialRepository")
interface CredentialRepository {
    /** Saves or replaces the value under `key`. */
    fun save(value: String, key: String)

    /** The value under `key`, or null when there is none or it can't be read. */
    fun get(key: String): String?

    /** Removes the value; true when it is gone afterwards. */
    fun delete(key: String): Boolean

    fun exists(key: String): Boolean = get(key) != null
}
