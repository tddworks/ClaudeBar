package com.tddworks.claudebar.providers

import platform.Foundation.NSUUID
import platform.Foundation.NSUserDefaults
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** UserDefaults as the old cards left it: read once, then removed. */
class UserDefaultsLegacyStoreTest {
    private val suite = "UserDefaultsLegacyStoreTest.${NSUUID().UUIDString}"
    private val defaults = NSUserDefaults(suiteName = suite)
    private val store = UserDefaultsLegacyStore(defaults)

    @AfterTest
    fun cleanUp() = defaults.removePersistentDomainForName(suite)

    @Test
    fun `should read a key an old card saved`() {
        defaults.setObject("old-key", "com.claudebar.credentials.deepseek-api-key")

        assertEquals("old-key", store.string("com.claudebar.credentials.deepseek-api-key"))
        assertTrue(store.contains("com.claudebar.credentials.deepseek-api-key"))
    }

    @Test
    fun `should have nothing once the key is removed`() {
        defaults.setObject("old-key", "com.claudebar.credentials.deepseek-api-key")

        store.remove("com.claudebar.credentials.deepseek-api-key")

        assertNull(store.string("com.claudebar.credentials.deepseek-api-key"))
        assertFalse(store.contains("com.claudebar.credentials.deepseek-api-key"))
    }

    @Test
    fun `should have nothing under a key never saved`() {
        assertNull(store.string("com.claudebar.credentials.never"))
        assertFalse(store.contains("com.claudebar.credentials.never"))
    }
}
