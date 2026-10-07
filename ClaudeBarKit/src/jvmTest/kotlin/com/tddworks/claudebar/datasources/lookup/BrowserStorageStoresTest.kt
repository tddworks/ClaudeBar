package com.tddworks.claudebar.datasources.lookup

import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.ByteArrayOutputStream
import java.io.File

/**
 * The browsers' local storage, read as SweetCookieKit read it: each Chromium profile's
 * `Local Storage/leveldb` — its `.log` and `.ldb` files, Snappy blocks and all — for one origin.
 */
class BrowserStorageStoresTest {
    @TempDir
    lateinit var home: File

    private val origin = "https://app.acme.test"

    /** A local-storage key: `_<origin>\0` and the key in Latin-1. */
    private fun key(name: String, at: String = origin) = byteArrayOf(0x5F) + at.toByteArray() + 0.toByte() + 1.toByte() + name.toByteArray()

    private fun value(text: String) = byteArrayOf(1) + text.toByteArray()

    private fun profile(relative: String, vararg files: Pair<String, ByteArray>, ago: Long = 0) {
        val profile = File(home, "Library/Application Support/$relative")
        File(profile, "Cookies").apply { parentFile.mkdirs(); writeText("cookies") }
        files.forEach { (name, bytes) ->
            File(profile, "Local Storage/leveldb/$name").apply {
                parentFile.mkdirs()
                writeBytes(bytes)
                setLastModified(System.currentTimeMillis() - ago * 1000)
            }
        }
    }

    @Test
    fun `should read a site's values from a profile's write-ahead log, the newest write winning and a deletion hiding a value`() {
        val log = logFile(
            batch(put(key("session"), value("old")), put(key("gone"), value("x"))),
            batch(put(key("session"), value("new")), delete(key("gone")), put(key("session", "https://other.test"), value("no"))),
        )
        profile("Google/Chrome/Default", "000003.log" to log)

        assertEquals(listOf(mapOf("session" to "new")), BrowserStorageStores(home.path).stores(origin))
    }

    @Test
    fun `should read a site's values from a profile's table, compressed or not`() {
        val entries = listOf(key("org") to value("org_1"), key("session") to value("from-table"))
        profile("Google/Chrome/Default", "000005.ldb" to table(entries, compressed = true))
        profile("Google/Chrome/Profile 1", "000005.ldb" to table(entries.take(1), compressed = false))

        assertEquals(
            listOf(mapOf("org" to "org_1", "session" to "from-table"), mapOf("org" to "org_1")),
            BrowserStorageStores(home.path).stores(origin),
        )
    }

    @Test
    fun `should read each profile once, beside its cookies, and pass over one with nothing for the site`() {
        profile("Google/Chrome/Default", "000003.log" to logFile(batch(put(key("session"), value("chrome")))))
        File(home, "Library/Application Support/Google/Chrome/Default/Network").mkdirs()
        File(home, "Library/Application Support/Google/Chrome/Default/Network/Cookies").writeText("cookies")
        profile("BraveSoftware/Brave-Browser/Default", "000003.log" to logFile(batch(put(key("other", "https://x.test"), value("x")))))
        profile("Microsoft Edge/Default", "000003.log" to logFile(batch(put(key("session"), value("edge")))))

        assertEquals(listOf(mapOf("session" to "chrome"), mapOf("session" to "edge")), BrowserStorageStores(home.path).stores(origin))
    }

    @Test
    fun `should read text stored as UTF-16, with a partition after the origin`() {
        val utf16 = byteArrayOf(0) + "token-16".toByteArray(Charsets.UTF_16LE)
        profile("Google/Chrome/Default", "000003.log" to logFile(batch(put(key("session", "$origin/^0https://top.test"), utf16))))

        assertEquals(listOf(mapOf("session" to "token-16")), BrowserStorageStores(home.path).stores(origin))
    }

    @Test
    fun `should expand Snappy literals and copies`() {
        // "abc", then a copy of six bytes from three back.
        val compressed = byteArrayOf(9, (2 shl 2).toByte(), 'a'.code.toByte(), 'b'.code.toByte(), 'c'.code.toByte(), (((6 - 4) shl 2) or 1).toByte(), 3)
        assertArrayEquals("abcabcabc".toByteArray(), Snappy.decompress(compressed))
    }

    // LevelDB files, written the way LevelDB writes them.

    private fun put(key: ByteArray, value: ByteArray) = byteArrayOf(1) + varint(key.size) + key + varint(value.size) + value
    private fun delete(key: ByteArray) = byteArrayOf(0) + varint(key.size) + key
    private fun batch(vararg records: ByteArray) = ByteArray(8) + le32(records.size) + records.reduce(ByteArray::plus)

    /** Each batch a FULL record: checksum, length, type 1. */
    private fun logFile(vararg batches: ByteArray): ByteArray =
        batches.fold(ByteArray(0)) { file, batch -> file + ByteArray(4) + le16(batch.size) + byteArrayOf(1) + batch }

    /** One data block of internal keys (sequence 1, a value), its index, and the footer. */
    private fun table(entries: List<Pair<ByteArray, ByteArray>>, compressed: Boolean): ByteArray {
        val data = block(entries.map { (key, value) -> key + byteArrayOf(1, 1, 0, 0, 0, 0, 0, 0) to value })
        val stored = if (compressed) snappyLiteral(data) else data
        val dataBlock = stored + byteArrayOf(if (compressed) 1 else 0) + ByteArray(4)
        val index = block(listOf("z".toByteArray() to varint(0) + varint(stored.size)))
        val indexBlock = index + byteArrayOf(0) + ByteArray(4)
        val handles = varint(0) + varint(0) + varint(dataBlock.size) + varint(index.size)
        val footer = handles + ByteArray(40 - handles.size) + ByteArray(8)
        return dataBlock + indexBlock + footer
    }

    private fun block(entries: List<Pair<ByteArray, ByteArray>>): ByteArray {
        val out = ByteArrayOutputStream()
        entries.forEach { (key, value) -> out.write(varint(0) + varint(key.size) + varint(value.size) + key + value) }
        out.write(le32(0))
        out.write(le32(1))
        return out.toByteArray()
    }

    private fun snappyLiteral(data: ByteArray): ByteArray {
        require(data.size in 61..256)
        return varint(data.size) + byteArrayOf((60 shl 2).toByte(), (data.size - 1).toByte()) + data
    }

    private fun varint(value: Int): ByteArray {
        val out = ByteArrayOutputStream()
        var rest = value
        while (rest >= 0x80) {
            out.write((rest and 0x7F) or 0x80)
            rest = rest ushr 7
        }
        out.write(rest)
        return out.toByteArray()
    }

    private fun le16(value: Int) = byteArrayOf(value.toByte(), (value shr 8).toByte())
    private fun le32(value: Int) = byteArrayOf(value.toByte(), (value shr 8).toByte(), (value shr 16).toByte(), (value shr 24).toByte())
}
