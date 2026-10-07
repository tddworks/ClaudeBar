package com.tddworks.claudebar.datasources.lookup

import com.tddworks.claudebar.datasources.BrowserCookie
import com.tddworks.claudebar.datasources.BrowserCookieReading
import com.tddworks.claudebar.datasources.BrowserStorageReading
import com.tddworks.claudebar.diagnostics.AppLog
import kotlinx.atomicfu.locks.SynchronizedObject
import kotlinx.atomicfu.locks.synchronized
import kotlinx.io.buffered
import kotlinx.io.files.Path
import kotlinx.io.files.SystemFileSystem
import kotlinx.io.files.SystemTemporaryDirectory
import kotlinx.io.readByteArray
import kotlin.random.Random

/** The Keychain's generic-password items, read by service and account — a Chromium browser's cookie password. */
internal interface SafeStorageKeychain {
    /** null when there is no such item, or the person refused. */
    fun password(service: String, account: String): String?
}

/** The two primitives a Chromium cookie's value is encrypted with on macOS. */
internal interface CookieCrypto {
    fun pbkdf2Sha1(password: ByteArray, salt: ByteArray, iterations: Int, length: Int): ByteArray?

    /** AES-128-CBC with PKCS#7 padding; null when the key, IV or padding doesn't fit. */
    fun aes128CbcDecrypt(data: ByteArray, key: ByteArray, iv: ByteArray): ByteArray?
}

/** One cookie database of one browser profile. */
internal data class CookieStore(val browser: WebBrowser, val database: String?)

/**
 * The browsers' cookie stores on this Mac, read the way SweetCookieKit read them for the Swift
 * app: every browser in [WebBrowser.importOrder], each profile's stores in order, unexpired
 * cookies whose domain ends with one of the domains. A browser whose stores can't be read is
 * passed over.
 */
internal class BrowserCookieStores(
    private val home: String,
    private val database: SQLiteReading,
    private val keychain: SafeStorageKeychain,
    private val crypto: CookieCrypto,
    /** Seconds since 1970. */
    private val now: () -> Double,
    private val browsers: List<WebBrowser> = WebBrowser.importOrder,
) : BrowserCookieReading {
    private val lock = SynchronizedObject()
    private val keys = mutableMapOf<WebBrowser, ByteArray>()

    override fun stores(domains: List<String>, names: List<String>): List<List<BrowserCookie>> {
        val found = mutableListOf<List<BrowserCookie>>()
        for (browser in browsers) {
            val stores = try {
                stores(browser).map { cookies(it, domains) }
            } catch (error: Exception) {
                AppLog.credentials.debug("${browser.displayName} cookies unreadable: ${error::class.simpleName}")
                continue
            }
            for (cookies in stores) {
                val named = cookies
                    .filter { it.domain.isNotEmpty() && it.name in names && (it.expiresSeconds == null || it.expiresSeconds >= now()) }
                    .map { BrowserCookie(it.name, it.value) }
                if (named.isNotEmpty()) found += named
            }
        }
        return found
    }

    /** A browser's stores, in the order they are asked. */
    fun stores(browser: WebBrowser): List<CookieStore> = when (browser.engine) {
        BrowserEngine.WEBKIT -> listOf(CookieStore(browser, null))
        BrowserEngine.CHROMIUM -> BrowserProfiles.chromiumDatabases(home, browser).map { CookieStore(browser, it) }
        BrowserEngine.GECKO -> BrowserProfiles.geckoDatabases(home, browser).map { CookieStore(browser, it) }
    }

    private fun cookies(store: CookieStore, domains: List<String>): List<StoredCookie> = when (store.browser.engine) {
        BrowserEngine.WEBKIT -> safari(domains)
        BrowserEngine.CHROMIUM -> withCopy(store.database!!) { chromium(it, store.browser, domains) }
        BrowserEngine.GECKO -> withCopy(store.database!!) { gecko(it, domains) }
    }

    private fun safari(domains: List<String>): List<StoredCookie> {
        val files = listOf(
            "$home/Library/Cookies/Cookies.binarycookies",
            "$home/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies",
        )
        for (file in files) {
            val cookies = runCatching { BinaryCookies.parse(bytes(file)) }.getOrNull() ?: continue
            return cookies.filter { CookieDomains.matches(it.domain, domains) }
        }
        throw IllegalStateException("Safari cookie file not found.")
    }

    private fun chromium(path: String, browser: WebBrowser, domains: List<String>): List<StoredCookie> {
        val key = key(browser)
        val hashed = runCatching {
            database.rows(path, "SELECT value FROM meta WHERE key = 'version'", "cookies")
                .firstOrNull()?.get("value")?.let { (it as? StoredValue.Text)?.text?.toIntOrNull() }
        }.getOrNull()?.let { it >= ChromiumCookies.HASHED_VERSION }
        val rows = database.rows(
            path,
            "SELECT host_key, name, value, encrypted_value, expires_utc FROM cookies WHERE ${CookieDomains.condition("host_key", domains)}",
            "cookies",
            limit = Int.MAX_VALUE,
        )
        return rows.mapNotNull { row ->
            val plain = row.text("value")
            val value = if (!plain.isNullOrEmpty()) plain
            else (row["encrypted_value"] as? StoredValue.Bytes)?.bytes?.takeIf { it.isNotEmpty() }
                ?.let { ChromiumCookies.decrypt(it, key, crypto, hashed) }
                ?: return@mapNotNull null
            StoredCookie(
                domain = CookieDomains.normalized(row.text("host_key") ?: return@mapNotNull null),
                name = row.text("name") ?: return@mapNotNull null,
                value = value,
                expiresSeconds = ChromiumCookies.expiry(row.text("expires_utc")?.toLongOrNull() ?: 0),
            )
        }
    }

    private fun gecko(path: String, domains: List<String>): List<StoredCookie> =
        database.rows(
            path,
            "SELECT host, name, value, expiry FROM moz_cookies WHERE ${CookieDomains.condition("host", domains)}",
            "cookies",
            limit = Int.MAX_VALUE,
        ).mapNotNull { row ->
            val expiry = row.text("expiry")?.toLongOrNull() ?: 0
            StoredCookie(
                domain = CookieDomains.normalized(row.text("host") ?: return@mapNotNull null),
                name = row.text("name") ?: return@mapNotNull null,
                value = row.text("value") ?: return@mapNotNull null,
                expiresSeconds = if (expiry > 0) expiry.toDouble() else null,
            )
        }

    /** The browser's cookie key, derived once from its Keychain password. */
    private fun key(browser: WebBrowser): ByteArray {
        synchronized(lock) { keys[browser] }?.let { return it }
        val password = browser.passwordLabels.firstNotNullOfOrNull { keychain.password(it.service, it.account) }
            ?: throw IllegalStateException("macOS Keychain denied access to ${browser.displayName} Safe Storage.")
        val key = ChromiumCookies.key(password, crypto) ?: throw IllegalStateException("Couldn't derive the cookie key.")
        synchronized(lock) { keys[browser] = key }
        return key
    }

    /**
     * Reads a copy of the database and its journal: a running browser holds its own locked, and
     * the copy is the only file ClaudeBar opens.
     */
    private fun <T> withCopy(path: String, read: (String) -> T): T {
        val folder = Path(SystemTemporaryDirectory, "claudebar-cookies-${Random.nextLong().toULong()}")
        SystemFileSystem.createDirectories(folder)
        try {
            val copy = Path(folder, Path(path).name)
            copyFile(path, copy.toString())
            for (suffix in listOf("-wal", "-shm")) {
                if (SystemFileSystem.exists(Path(path + suffix))) runCatching { copyFile(path + suffix, copy.toString() + suffix) }
            }
            return read(copy.toString())
        } finally {
            runCatching {
                SystemFileSystem.list(folder).forEach { SystemFileSystem.delete(it, mustExist = false) }
                SystemFileSystem.delete(folder, mustExist = false)
            }
        }
    }

    private fun copyFile(from: String, to: String) {
        val data = bytes(from)
        SystemFileSystem.sink(Path(to)).buffered().use { it.write(data) }
    }

    private fun bytes(path: String): ByteArray = SystemFileSystem.source(Path(path)).buffered().use { it.readByteArray() }

    private fun Map<String, StoredValue>.text(column: String): String? = when (val value = this[column]) {
        is StoredValue.Text -> value.text
        is StoredValue.Bytes -> StoredText.utf8(value.bytes)
        null -> null
    }
}

/**
 * The browsers' local storage on this Mac: each Chromium profile's `Local Storage/leveldb`, found
 * beside its cookies, in import order, one map per profile that keeps anything for the origin.
 */
internal class BrowserStorageStores(
    private val home: String,
    private val browsers: List<WebBrowser> = WebBrowser.importOrder,
) : BrowserStorageReading {
    override fun stores(origin: String): List<Map<String, String>> {
        val seen = mutableSetOf<String>()
        val found = mutableListOf<Map<String, String>>()
        for (browser in browsers) {
            if (browser.engine != BrowserEngine.CHROMIUM) continue
            for (database in BrowserProfiles.chromiumDatabases(home, browser)) {
                val profile = BrowserProfiles.profileFolder(database)
                if (!seen.add(profile)) continue
                val leveldb = "$profile/Local Storage/leveldb"
                if (!SystemFileSystem.exists(Path(leveldb))) continue
                val values = LocalStorage.values(origin, leveldb)
                if (values.isNotEmpty()) found += values
            }
        }
        return found
    }
}

/** Where each browser keeps its profiles. */
internal object BrowserProfiles {
    /** Each profile's `Network/Cookies`, then its `Cookies` — those that exist — profiles in name order. */
    fun chromiumDatabases(home: String, browser: WebBrowser): List<String> {
        val root = browser.profileRoot ?: return emptyList()
        return folders("$home/Library/Application Support/$root")
            .filter { it == "Default" || it.startsWith("Profile ") || it.startsWith("user-") }
            .sorted()
            .flatMap { name ->
                val profile = "$home/Library/Application Support/$root/$name"
                listOf("$profile/Network/Cookies", "$profile/Cookies")
            }
            .filter { SystemFileSystem.exists(Path(it)) }
    }

    /** Each profile's `cookies.sqlite`, the `default-release` profile first, then `default`, then the rest. */
    fun geckoDatabases(home: String, browser: WebBrowser): List<String> {
        val folder = browser.geckoFolder ?: return emptyList()
        val root = "$home/Library/Application Support/$folder/Profiles"
        return folders(root)
            .sortedWith(compareBy({ rank(it) }, { it.lowercase() }))
            .map { "$root/$it/cookies.sqlite" }
            .filter { SystemFileSystem.exists(Path(it)) }
    }

    /** The profile folder a cookie database lives in: `…/Default/Cookies` or `…/Default/Network/Cookies`. */
    fun profileFolder(database: String): String {
        val folder = database.substringBeforeLast('/')
        return if (folder.substringAfterLast('/') == "Network") folder.substringBeforeLast('/') else folder
    }

    private fun rank(name: String): Int = name.lowercase().let {
        when {
            "default-release" in it -> 0
            "default" in it -> 1
            else -> 2
        }
    }

    private fun folders(path: String): List<String> =
        runCatching { SystemFileSystem.list(Path(path)) }.getOrDefault(emptyList())
            .filter { !it.name.startsWith(".") && SystemFileSystem.metadataOrNull(it)?.isDirectory == true }
            .map { it.name }
}

/** Which cookie domains a query's domains mean: a suffix match, ignoring a leading dot and case. */
internal object CookieDomains {
    fun normalized(raw: String): String = raw.trim().removePrefix(".")

    fun matches(domain: String, patterns: List<String>): Boolean {
        if (patterns.isEmpty()) return true
        val haystack = normalized(domain).lowercase()
        return patterns.any { haystack.endsWith(normalized(it).lowercase()) }
    }

    /** The same rule as SQL over [column]. */
    fun condition(column: String, patterns: List<String>): String {
        if (patterns.isEmpty()) return "1=1"
        return patterns.joinToString(" OR ") { "$column LIKE '%${it.replace("'", "''")}'" }
    }
}

/**
 * A Chromium cookie's value on macOS: `v10` + AES-128-CBC (IV of sixteen spaces, PKCS#7) under a
 * key derived from the browser's Keychain password with PBKDF2-HMAC-SHA1 (salt `saltysalt`, 1003
 * rounds). Since database version 24 the plaintext starts with a SHA-256 of the cookie's domain.
 */
internal object ChromiumCookies {
    const val HASHED_VERSION = 24
    private val salt = "saltysalt".encodeToByteArray()
    private val iv = ByteArray(16) { 0x20 }

    fun key(password: String, crypto: CookieCrypto): ByteArray? = crypto.pbkdf2Sha1(password.encodeToByteArray(), salt, 1003, 16)

    /**
     * The value, or null when it isn't `v10` or doesn't decrypt. [hashed] says whether a domain
     * hash leads the plaintext; when unknown, SweetCookieKit's guess: any plaintext over 32 bytes.
     */
    fun decrypt(encrypted: ByteArray, key: ByteArray, crypto: CookieCrypto, hashed: Boolean? = null): String? {
        if (encrypted.size <= 3 || encrypted.copyOfRange(0, 3).decodeToString() != "v10") return null
        val plain = crypto.aes128CbcDecrypt(encrypted.copyOfRange(3, encrypted.size), key, iv) ?: return null
        val strip = hashed ?: (plain.size > 32)
        val candidate = if (strip && plain.size >= 32) plain.copyOfRange(32, plain.size) else plain
        val text = StoredText.utf8(candidate) ?: StoredText.utf8(plain) ?: return null
        return text.dropWhile { it.code < 0x20 }
    }

    /** `expires_utc`: microseconds since 1601; null for a session cookie. */
    fun expiry(expiresUTC: Long): Double? {
        if (expiresUTC <= 0) return null
        val seconds = expiresUTC / 1_000_000.0 - 11_644_473_600.0
        return seconds.takeIf { it > 0 }
    }
}
