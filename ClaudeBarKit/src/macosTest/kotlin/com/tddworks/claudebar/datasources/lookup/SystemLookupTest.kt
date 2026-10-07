package com.tddworks.claudebar.datasources.lookup

import kotlin.random.Random
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNull

/** The Mac's own pieces the lookup reads through: CommonCrypto, `/usr/bin/security`, the Keychain, libsqlite3. */
class SystemLookupTest {
    private val scratch = Scratch()

    @AfterTest
    fun cleanUp() = scratch.remove()

    private fun bytes(hex: String) = hex.chunked(2).map { it.toInt(16).toByte() }.toByteArray()

    @Test
    fun `should derive a cookie key as PBKDF2-HMAC-SHA1 does`() {
        // RFC 6070's first vector, and Chromium's own parameters.
        assertEquals("0c60c80f961f0e71f3a9b524af6012062fe037a6",
            hex(CommonCryptoCookies.pbkdf2Sha1("password".encodeToByteArray(), "salt".encodeToByteArray(), 1, 20)!!))
        assertEquals("d9a09d499b4e1b7461f28e67972c6dbd", hex(ChromiumCookies.key("peanuts", CommonCryptoCookies)!!))
    }

    @Test
    fun `should decrypt a Chromium cookie value encrypted under the browser's key`() {
        val encrypted = "v10".encodeToByteArray() + bytes("7f8e2bacb048250dcf41ae2249419436")

        assertEquals("session-value", ChromiumCookies.decrypt(encrypted, bytes("d9a09d499b4e1b7461f28e67972c6dbd"), CommonCryptoCookies, hashed = false))
        assertNull(ChromiumCookies.decrypt(encrypted, ByteArray(16), CommonCryptoCookies, hashed = false))
    }

    @Test
    fun `should report a Keychain item that isn't there as a failed security run`() {
        val result = SystemSecurityTool.run(listOf("find-generic-password", "-s", "com.tddworks.claudebar.tests.${Random.nextLong().toULong()}", "-w"))

        assertNotEquals(0, result.status)
    }

    @Test
    fun `should find no browser password the Keychain doesn't hold`() {
        assertNull(KeychainSafeStorage.password("com.tddworks.claudebar.tests.${Random.nextLong().toULong()} Safe Storage", "nobody"))
    }

    @Test
    fun `should read a Chromium profile's cookies from a copy of its database`() {
        scratch.database(
            "CREATE TABLE meta(key TEXT, value TEXT); INSERT INTO meta VALUES ('version', '18');" +
                "CREATE TABLE cookies(host_key TEXT, name TEXT, value TEXT, encrypted_value BLOB, expires_utc INTEGER);" +
                "INSERT INTO cookies VALUES ('.acme.test', 'session', '', X'${hex("v10".encodeToByteArray())}7f8e2bacb048250dcf41ae2249419436', 0);" +
                "INSERT INTO cookies VALUES ('.other.test', 'session', 'other', X'', 0);",
            "Library/Application Support/Google/Chrome/Default/Cookies",
        )
        val stores = BrowserCookieStores(
            scratch.root, SystemSQLite(),
            object : SafeStorageKeychain {
                override fun password(service: String, account: String) = if (service == "Chrome Safe Storage") "peanuts" else null
            },
            CommonCryptoCookies, now = { 0.0 }, browsers = listOf(WebBrowser.CHROME),
        )

        assertEquals("session-value", stores.stores(listOf("acme.test"), listOf("session")).single().single().value)
    }
}
