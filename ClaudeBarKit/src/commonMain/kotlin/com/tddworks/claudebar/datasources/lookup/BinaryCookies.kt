package com.tddworks.claudebar.datasources.lookup

/** One cookie a browser store holds. Its value never enters a log. */
internal data class StoredCookie(
    /** Without a leading dot. */
    val domain: String,
    val name: String,
    val value: String,
    /** Seconds since 1970; null for a session cookie. */
    val expiresSeconds: Double? = null,
)

/**
 * Safari's `Cookies.binarycookies`: a big-endian header (`cook`, the page count, each page's
 * size), then pages of little-endian cookie records. Best effort — a record that doesn't fit is
 * skipped; a file that isn't one is refused.
 */
internal object BinaryCookies {
    /** Seconds from 1970 to 2001, the Mac's reference date. */
    private const val REFERENCE_DATE = 978_307_200.0

    class InvalidFile : Exception("Safari cookie file is invalid.")

    fun parse(data: ByteArray): List<StoredCookie> {
        if (data.size < 8 || data.decodeToString(0, 4) != "cook") throw InvalidFile()
        val pageCount = uint32BE(data, 4)
        if (pageCount < 0 || 8 + pageCount * 4 > data.size) throw InvalidFile()
        val sizes = (0 until pageCount.toInt()).map { uint32BE(data, 8 + it * 4) }
        var offset = 8L + pageCount * 4
        val cookies = mutableListOf<StoredCookie>()
        for (size in sizes) {
            if (offset + size > data.size) throw InvalidFile()
            cookies += page(data.copyOfRange(offset.toInt(), (offset + size).toInt()))
            offset += size
        }
        return cookies
    }

    private fun page(data: ByteArray): List<StoredCookie> {
        if (data.size < 8) return emptyList()
        val count = uint32LE(data, 4)
        if (count <= 0 || 8 + count * 4 > data.size) return emptyList()
        return (0 until count.toInt()).mapNotNull { index ->
            val offset = uint32LE(data, 8 + index * 4).toInt()
            if (offset < 0 || offset + 56 > data.size) null else record(data, offset)
        }
    }

    private fun record(data: ByteArray, offset: Int): StoredCookie? {
        val size = uint32LE(data, offset)
        if (size <= 0 || offset + size > data.size) return null
        val domain = text(data, offset, uint32LE(data, offset + 16)) ?: ""
        val name = text(data, offset, uint32LE(data, offset + 20)) ?: ""
        val value = text(data, offset, uint32LE(data, offset + 28)) ?: ""
        if (domain.isEmpty() || name.isEmpty()) return null
        val expires = Double.fromBits(uint64LE(data, offset + 40))
        return StoredCookie(
            domain = domain.trim().removePrefix("."),
            name = name,
            value = value,
            expiresSeconds = if (expires > 0) expires + REFERENCE_DATE else null,
        )
    }

    /** The NUL-terminated UTF-8 text at [offset] within the record at [base]. */
    private fun text(data: ByteArray, base: Int, offset: Long): String? {
        val start = base + offset
        if (start < 0 || start >= data.size) return null
        var end = start.toInt()
        while (end < data.size && data[end] != 0.toByte()) end++
        if (end <= start) return null
        return StoredText.utf8(data.copyOfRange(start.toInt(), end))
    }

    private fun byte(data: ByteArray, at: Int): Long = (data[at].toLong() and 0xFF)

    private fun uint32BE(data: ByteArray, at: Int): Long =
        (byte(data, at) shl 24) or (byte(data, at + 1) shl 16) or (byte(data, at + 2) shl 8) or byte(data, at + 3)

    private fun uint32LE(data: ByteArray, at: Int): Long =
        byte(data, at) or (byte(data, at + 1) shl 8) or (byte(data, at + 2) shl 16) or (byte(data, at + 3) shl 24)

    private fun uint64LE(data: ByteArray, at: Int): Long = (0 until 8).fold(0L) { value, index -> value or (byte(data, at + index) shl (8 * index)) }
}
