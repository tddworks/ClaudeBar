package com.tddworks.claudebar.providers

import platform.Foundation.NSUserDefaults

/** UserDefaults, where earlier releases kept a few provider settings and keys in plain text. */
internal class UserDefaultsLegacyStore(
    private val defaults: NSUserDefaults = NSUserDefaults.standardUserDefaults,
) : LegacyStore {
    override fun string(key: String): String? = defaults.stringForKey(key)

    override fun contains(key: String): Boolean = defaults.objectForKey(key) != null

    override fun remove(key: String) = defaults.removeObjectForKey(key)
}
