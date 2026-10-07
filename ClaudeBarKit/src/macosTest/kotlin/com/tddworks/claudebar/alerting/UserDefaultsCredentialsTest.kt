package com.tddworks.claudebar.alerting

import platform.Foundation.NSUserDefaults
import kotlin.random.Random
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Against real UserDefaults, in a suite no one else uses. */
class UserDefaultsCredentialsTest {
    private val suiteName = "com.tddworks.claudebar.tests.${Random.nextLong().toULong()}"
    private val defaults = NSUserDefaults(suiteName = suiteName)
    private val credentials = UserDefaultsCredentials(defaults)

    @AfterTest
    fun forget() {
        defaults.removePersistentDomainForName(suiteName)
    }

    @Test
    fun `should give back a saved secret`() {
        credentials.save("s3cret", "token")
        assertEquals("s3cret", credentials.get("token"))
        assertTrue(credentials.exists("token"))
    }

    @Test
    fun `should keep a secret under the prefix earlier releases used`() {
        credentials.save("s3cret", "notify-device-token")
        assertEquals("s3cret", defaults.stringForKey("com.claudebar.credentials.notify-device-token"))
    }

    @Test
    fun `should forget a deleted secret`() {
        credentials.save("gone", "token")
        assertTrue(credentials.delete("token"))
        assertNull(credentials.get("token"))
        assertFalse(credentials.exists("token"))
    }
}
