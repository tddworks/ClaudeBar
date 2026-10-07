package com.tddworks.claudebar.storage

import kotlin.random.Random
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Against the real login Keychain, under a service no one else uses. */
class KeychainCredentialsTest {
    private val keychain = KeychainCredentials("com.tddworks.claudebar.tests.${Random.nextLong().toULong()}")

    @AfterTest
    fun forget() {
        keychain.delete("token")
    }

    @Test
    fun `should give back a saved secret`() {
        keychain.save("s3cret", "token")
        assertEquals("s3cret", keychain.get("token"))
        assertTrue(keychain.exists("token"))
    }

    @Test
    fun `should replace a secret saved again`() {
        keychain.save("old", "token")
        keychain.save("new", "token")
        assertEquals("new", keychain.get("token"))
    }

    @Test
    fun `should forget a deleted secret`() {
        keychain.save("gone", "token")
        assertTrue(keychain.delete("token"))
        assertNull(keychain.get("token"))
        assertFalse(keychain.exists("token"))
    }

    @Test
    fun `should count deleting a never-saved secret as done`() {
        assertTrue(keychain.delete("token"))
    }
}
