package com.tddworks.claudebar.datasources.lookup

import com.tddworks.claudebar.datasources.BrowserCookie
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest

/**
 * The browsers' cookie stores, read as SweetCookieKit read them for the Swift app: Safari's
 * `Cookies.binarycookies`, Chromium's encrypted `Cookies` databases and Firefox's
 * `cookies.sqlite`, in the same browser and profile order, expired cookies left out.
 */
class BrowserCookieStoresTest {
    @TempDir
    lateinit var home: File

    private val now = 1_800_000_000.0
    private val chromePassword = "peanuts"

    private fun file(relative: String, contents: ByteArray): File =
        File(home, relative).apply { parentFile.mkdirs(); writeBytes(contents) }

    /** A cookie database whose rows the fake answers by what the file holds. */
    private fun database(relative: String, name: String) = file(relative, name.encodeToByteArray())

    private fun stores(
        tables: Map<String, List<Map<String, StoredValue>>> = emptyMap(),
        version: String = "24",
        passwords: Map<SafeStorageLabel, String> = mapOf(SafeStorageLabel("Chrome Safe Storage", "Chrome") to chromePassword),
    ) = BrowserCookieStores(
        home.path,
        FakeDatabase { contents, query -> if ("FROM meta" in query) listOf(mapOf("value" to text(version))) else tables[contents].orEmpty() },
        FakeKeychain(passwords),
        JdkCrypto,
        now = { now },
    )

    private fun chromeRow(name: String, value: String, host: String = ".acme.test", hashed: Boolean = true): Map<String, StoredValue> {
        val hash = if (hashed) MessageDigest.getInstance("SHA-256").digest(host.removePrefix(".").toByteArray()) else ByteArray(0)
        return mapOf(
            "host_key" to text(host), "name" to text(name), "value" to text(""),
            "encrypted_value" to StoredValue.Bytes(JdkCrypto.encrypt(hash + value.toByteArray(), chromePassword)),
            "expires_utc" to text("0"),
        )
    }

    @Test
    fun `should read Safari's cookies for the site, leaving out expired ones and other sites`() {
        file("Library/Cookies/Cookies.binarycookies", binaryCookies(
            Triple(".acme.test", "session", "s-safari") to now + 3600,
            Triple("acme.test", "session", "s-old") to now - 3600,
            Triple("other.test", "session", "s-other") to null,
        ))

        assertEquals(listOf(listOf(BrowserCookie("session", "s-safari"))), stores().stores(listOf("acme.test"), listOf("session")))
    }

    @Test
    fun `should decrypt a Chromium cookie with the key the browser's Keychain password derives`() {
        database("Library/Application Support/Google/Chrome/Default/Cookies", "chrome-default")

        val found = stores(mapOf("chrome-default" to listOf(chromeRow("session", "s-chrome")))).stores(listOf("acme.test"), listOf("session"))

        assertEquals(listOf(listOf(BrowserCookie("session", "s-chrome"))), found)
    }

    @Test
    fun `should keep a long Chromium cookie whole when its database predates the domain hash`() {
        database("Library/Application Support/Google/Chrome/Default/Cookies", "chrome-default")
        val long = "x".repeat(48)

        val found = stores(mapOf("chrome-default" to listOf(chromeRow("session", long, hashed = false))), version = "18")
            .stores(listOf("acme.test"), listOf("session"))

        assertEquals(long, found.single().single().value)
    }

    @Test
    fun `should ask each profile's network store before its own, profiles in name order, after Safari`() {
        file("Library/Cookies/Cookies.binarycookies", binaryCookies(Triple("acme.test", "session", "safari") to null))
        database("Library/Application Support/Google/Chrome/Profile 1/Cookies", "profile-1")
        database("Library/Application Support/Google/Chrome/Default/Cookies", "default")
        database("Library/Application Support/Google/Chrome/Default/Network/Cookies", "default-network")
        database("Library/Application Support/Google/Chrome/System Profile/Cookies", "never")
        val tables = listOf("profile-1", "default", "default-network", "never").associateWith { listOf(chromeRow("session", it)) }

        val found = stores(tables).stores(listOf("acme.test"), listOf("session")).map { it.single().value }

        assertEquals(listOf("safari", "default-network", "default", "profile-1"), found)
    }

    @Test
    fun `should pass over a Chromium browser whose Keychain password is refused for the next browser`() {
        database("Library/Application Support/Google/Chrome/Default/Cookies", "chrome")
        database("Library/Application Support/Firefox/Profiles/abc.default-release/cookies.sqlite", "firefox")
        val tables = mapOf(
            "chrome" to listOf(chromeRow("session", "s-chrome")),
            "firefox" to listOf(mapOf("host" to text(".acme.test"), "name" to text("session"), "value" to text("s-fox"), "expiry" to text("0"))),
        )

        val found = stores(tables, passwords = emptyMap()).stores(listOf("acme.test"), listOf("session"))

        assertEquals(listOf(listOf(BrowserCookie("session", "s-fox"))), found)
    }

    @Test
    fun `should read Firefox's default-release profile first and leave out its expired cookies`() {
        database("Library/Application Support/Firefox/Profiles/zzz.default-release/cookies.sqlite", "release")
        database("Library/Application Support/Firefox/Profiles/aaa.work/cookies.sqlite", "work")
        fun row(value: String, expiry: Double) =
            mapOf("host" to text("acme.test"), "name" to text("session"), "value" to text(value), "expiry" to text(expiry.toLong().toString()))
        val tables = mapOf("release" to listOf(row("release", now + 60), row("stale", now - 60)), "work" to listOf(row("work", now + 60)))

        val found = stores(tables).stores(listOf("acme.test"), listOf("session"))

        assertEquals(listOf(listOf(BrowserCookie("session", "release")), listOf(BrowserCookie("session", "work"))), found)
    }

    @Test
    fun `should ask a database for the domains as a suffix, a quote kept a quote`() {
        assertEquals("host_key LIKE '%acme.test' OR host_key LIKE '%o''hare.test'", CookieDomains.condition("host_key", listOf("acme.test", "o'hare.test")))
        assertTrue(CookieDomains.matches(".api.acme.test", listOf("acme.test")))
    }

    @Test
    fun `should read a Chromium cookie's expiry from microseconds since 1601`() {
        assertEquals(1_700_000_000.0, ChromiumCookies.expiry((1_700_000_000L + 11_644_473_600L) * 1_000_000)!!, 1e-3)
        assertNull(ChromiumCookies.expiry(0))
    }

    @Test
    fun `should try a browser's own Keychain item before the ones it may share`() {
        assertEquals(SafeStorageLabel("Brave Safe Storage", "Brave"), WebBrowser.BRAVE.passwordLabels.first())
        assertEquals(SafeStorageLabel("Chrome Safe Storage", "Chrome"), WebBrowser.CHROME_BETA.passwordLabels.first())
        assertEquals(WebBrowser.SAFARI, WebBrowser.importOrder.first())
        assertEquals(WebBrowser.EDGE_CANARY, WebBrowser.importOrder.last())
    }
}

/** A `Cookies.binarycookies` file of one page: (domain, name, value) and when each expires. */
internal fun binaryCookies(vararg cookies: Pair<Triple<String, String, String>, Double?>): ByteArray {
    val records = cookies.map { (cookie, expires) ->
        val strings = listOf(cookie.first, cookie.second, "/", cookie.third).map { it.toByteArray() + 0.toByte() }
        var offset = 56
        val offsets = strings.map { string -> offset.also { offset += string.size } }
        val header = ByteBuffer.allocate(56).order(ByteOrder.LITTLE_ENDIAN)
            .putInt(56 + strings.sumOf { it.size }).putInt(0).putInt(1).putInt(0)
            .putInt(offsets[0]).putInt(offsets[1]).putInt(offsets[2]).putInt(offsets[3])
            .putLong(0)
            .putDouble(expires?.let { it - 978_307_200.0 } ?: 0.0)
            .putDouble(0.0)
        header.array() + strings.reduce(ByteArray::plus)
    }
    val pageHeader = 8 + records.size * 4 + 4
    var at = pageHeader
    val page = ByteArrayOutputStream()
    page.write(byteArrayOf(0, 0, 1, 0))
    page.write(le(records.size))
    records.forEach { page.write(le(at)); at += it.size }
    page.write(le(0))
    records.forEach(page::write)
    val bytes = page.toByteArray()
    return "cook".toByteArray() + be(1) + be(bytes.size) + bytes
}

private fun le(value: Int) = ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(value).array()
private fun be(value: Int) = ByteBuffer.allocate(4).order(ByteOrder.BIG_ENDIAN).putInt(value).array()
