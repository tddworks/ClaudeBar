package com.tddworks.claudebar.datasources.lookup

/**
 * A Chromium profile's `Local Storage/leveldb`, read for one origin. A key is `_<origin>\0<key>`;
 * text is stored with a one-byte prefix — 0 for UTF-16LE, 1 for Latin-1. The newest write of a
 * key wins, and a deletion hides every older one.
 */
internal object LocalStorage {
    /** Every key and value the folder keeps for [origin]. */
    fun values(origin: String, folder: String): Map<String, String> = values(origin, LevelDB.entries(folder).orEmpty())

    fun values(origin: String, entries: List<LevelDBEntry>): Map<String, String> {
        val requested = normalized(origin)
        val values = mutableMapOf<String, String>()
        val tombstones = mutableSetOf<String>()
        for (entry in entries) {
            val (entryOrigin, key) = storageKey(entry.key) ?: continue
            if (!originMatches(normalized(entryOrigin), requested)) continue
            if (entry.isDeletion) {
                tombstones += key
                values.remove(key)
                continue
            }
            if (key in tombstones || key in values) continue
            // Entries are newest first: the first value seen is the current one.
            storedValue(entry.value)?.let { values[key] = it }
        }
        return values
    }

    private fun storageKey(data: ByteArray): Pair<String, String>? =
        storageKey(data, start = 1, requiresPrefix = true) ?: storageKey(data, start = 0, requiresPrefix = false)

    private fun storageKey(data: ByteArray, start: Int, requiresPrefix: Boolean): Pair<String, String>? {
        if (requiresPrefix && data.firstOrNull() != 0x5F.toByte()) return null
        val split = (start until data.size).firstOrNull { data[it] == 0.toByte() } ?: return null
        if (split + 1 >= data.size) return null
        val originText = text(data.copyOfRange(start, split)) ?: return null
        val keyData = data.copyOfRange(split + 1, data.size)
        val key = prefixed(keyData) ?: text(keyData) ?: return null
        val origin = storageKeyOrigin(originText)
        if (!requiresPrefix && !looksLikeOrigin(origin)) return null
        return origin to key
    }

    private fun looksLikeOrigin(value: String): Boolean {
        val trimmed = value.trim()
        if (trimmed.isEmpty()) return false
        if ("://" in trimmed) return true
        if (trimmed == "localhost" || trimmed.startsWith("localhost:")) return true
        return '.' in trimmed
    }

    private fun storedValue(data: ByteArray): String? = if (data.isEmpty()) null else prefixed(data) ?: text(data)

    private fun text(data: ByteArray): String? {
        if (data.isEmpty()) return null
        val decoded = prefixed(data)
            ?: (if (looksUTF16(data)) StoredText.utf16LittleEndian(data) else null)
            ?: StoredText.utf8(data)
            ?: StoredText.utf16LittleEndian(data)
            ?: StoredText.latin1(data)
        return decoded.trim { it.isISOControl() }
    }

    private fun prefixed(data: ByteArray): String? {
        if (data.size <= 1) return null
        val payload = data.copyOfRange(1, data.size)
        return when (data[0].toInt()) {
            0 -> StoredText.utf16LittleEndian(payload)
            1 -> StoredText.latin1(payload)
            else -> null
        }
    }

    private fun looksUTF16(data: ByteArray): Boolean {
        if (data.size < 6 || data.size % 2 != 0) return false
        val sample = data.copyOfRange(0, minOf(64, data.size))
        val odd = (1 until sample.size step 2).toList()
        if (odd.size < 4) return false
        return odd.count { sample[it] == 0.toByte() }.toDouble() / odd.size > 0.6
    }

    private fun normalized(origin: String): String = origin.trim().removeSuffix("/")

    /** Chromium's StorageKey serialisation: the origin, before any `^` partition attributes. */
    private fun storageKeyOrigin(value: String): String {
        val trimmed = value.trim()
        if (trimmed.isEmpty()) return trimmed
        var origin = trimmed.substringBefore('^')
        val scheme = origin.indexOf("://")
        val slash = if (scheme >= 0) origin.indexOf('/', scheme + 3) else origin.indexOf('/')
        if (slash >= 0) origin = origin.substring(0, slash)
        return origin.removeSuffix("/")
    }

    private fun originMatches(stored: String, requested: String): Boolean {
        if (stored == requested) return true
        val storedHost = host(stored)
        if (storedHost != null && storedHost == host(requested)) return true
        return stored == requested.substringAfter("://")
    }

    /** `host[:port]` of an origin. */
    private fun host(value: String): String? = value.substringAfter("://").split('/').firstOrNull()?.takeIf { it.isNotEmpty() }
}
