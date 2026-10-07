package com.tddworks.claudebar.datasources.lookup

import com.tddworks.claudebar.datasources.modifiedSeconds
import kotlinx.io.buffered
import kotlinx.io.files.Path
import kotlinx.io.files.SystemFileSystem
import kotlinx.io.readByteArray

/** One write a LevelDB store holds: a key and its value, or the key's deletion. */
internal class LevelDBEntry(val key: ByteArray, val value: ByteArray, val isDeletion: Boolean)

/**
 * A LevelDB folder read without LevelDB — its `.log` write-ahead files and `.ldb` tables, newest
 * file first, each newest-first within. Best effort, as SweetCookieKit's was: a block that doesn't
 * parse is skipped, never fatal.
 */
internal object LevelDB {
    private const val BLOCK_SIZE = 32 * 1024
    private const val FOOTER_SIZE = 48

    /** Every entry in the folder's files, newest file first; null when the folder can't be listed. */
    fun entries(folder: String): List<LevelDBEntry>? {
        val files = runCatching { SystemFileSystem.list(Path(folder)) }.getOrNull() ?: return null
        return files
            .filter { !it.name.startsWith(".") && it.name.substringAfterLast('.', "").lowercase() in setOf("ldb", "log") }
            .sortedByDescending { modifiedSeconds(it.toString()) ?: Double.NEGATIVE_INFINITY }
            .flatMap { file ->
                val data = runCatching { SystemFileSystem.source(file).buffered().use { it.readByteArray() } }.getOrNull()
                    ?: return@flatMap emptyList()
                if (file.name.lowercase().endsWith(".log")) logEntries(data) else tableEntries(data)
            }
    }

    /** A `.log` file's write batches, newest first. */
    fun logEntries(data: ByteArray): List<LevelDBEntry> {
        val entries = mutableListOf<LevelDBEntry>()
        var record = ByteArray(0)
        var offset = 0
        while (offset < data.size) {
            val blockEnd = minOf(offset + BLOCK_SIZE, data.size)
            var at = offset
            while (at + 7 <= blockEnd) {
                val length = uint16LE(data, at + 4)
                val type = data[at + 6].toInt()
                at += 7
                if (length == 0) continue
                if (at + length > blockEnd) break
                val chunk = data.copyOfRange(at, at + length)
                at += length
                when (type) {
                    1 -> entries += writeBatch(chunk)
                    2 -> record = chunk
                    3 -> record += chunk
                    4 -> {
                        entries += writeBatch(record + chunk)
                        record = ByteArray(0)
                    }
                }
            }
            offset += BLOCK_SIZE
        }
        if (record.isNotEmpty()) entries += writeBatch(record)
        return entries.reversed()
    }

    private fun writeBatch(data: ByteArray): List<LevelDBEntry> {
        if (data.size < 12) return emptyList()
        val entries = mutableListOf<LevelDBEntry>()
        val reader = Bytes(data, 12)
        while (reader.hasMore) {
            when (reader.byte()) {
                0 -> entries += LevelDBEntry(reader.slice() ?: break, ByteArray(0), isDeletion = true)
                1 -> {
                    val key = reader.slice() ?: break
                    val value = reader.slice() ?: break
                    entries += LevelDBEntry(key, value, isDeletion = false)
                }
                else -> return entries
            }
        }
        return entries
    }

    /** An `.ldb` table's entries, in its index's order. */
    fun tableEntries(data: ByteArray): List<LevelDBEntry> {
        if (data.size < FOOTER_SIZE) return emptyList()
        val footer = Bytes(data.copyOfRange(data.size - FOOTER_SIZE, data.size - 8), 0)
        footer.handle() ?: return emptyList()
        val index = footer.handle()?.let { block(data, it) } ?: return emptyList()
        return dataBlock(index, internalKeys = false).flatMap { entry ->
            val handle = Bytes(entry.value, 0).handle() ?: return@flatMap emptyList()
            block(data, handle)?.let { dataBlock(it, internalKeys = true) }.orEmpty()
        }
    }

    private fun block(data: ByteArray, handle: Pair<Long, Long>): ByteArray? {
        val start = handle.first
        val end = handle.first + handle.second
        if (start < 0 || end + 5 > data.size) return null
        val raw = data.copyOfRange(start.toInt(), end.toInt())
        return when (data[end.toInt()].toInt()) {
            0 -> raw
            1 -> Snappy.decompress(raw)
            else -> null
        }
    }

    private fun dataBlock(data: ByteArray, internalKeys: Boolean): List<LevelDBEntry> {
        if (data.size < 4) return emptyList()
        val restarts = uint32LE(data, data.size - 4)
        val restartBytes = (restarts + 1) * 4
        if (data.size < restartBytes) return emptyList()
        val limit = (data.size - restartBytes).toInt()
        val entries = mutableListOf<LevelDBEntry>()
        val reader = Bytes(data, 0)
        var lastKey = ByteArray(0)
        while (reader.at < limit) {
            val shared = reader.varint32() ?: break
            val nonShared = reader.varint32() ?: break
            val valueLength = reader.varint32() ?: break
            if (reader.at + nonShared > limit) break
            val suffix = data.copyOfRange(reader.at, reader.at + nonShared.toInt())
            reader.at += nonShared.toInt()
            if (reader.at + valueLength > limit) break
            val value = data.copyOfRange(reader.at, reader.at + valueLength.toInt())
            reader.at += valueLength.toInt()
            val key = lastKey.copyOfRange(0, minOf(shared.toInt(), lastKey.size)) + suffix
            lastKey = key
            entries += if (internalKeys && key.size >= 8) {
                val userKey = key.copyOfRange(0, key.size - 8)
                if (key[key.size - 8].toInt() == 0) LevelDBEntry(userKey, ByteArray(0), isDeletion = true)
                else LevelDBEntry(userKey, value, isDeletion = false)
            } else {
                LevelDBEntry(key, value, isDeletion = false)
            }
        }
        return entries
    }

    private fun uint16LE(data: ByteArray, at: Int): Int = (data[at].toInt() and 0xFF) or ((data[at + 1].toInt() and 0xFF) shl 8)

    private fun uint32LE(data: ByteArray, at: Int): Long =
        (0 until 4).fold(0L) { value, index -> value or ((data[at + index].toLong() and 0xFF) shl (8 * index)) }

    /** A cursor over bytes: varints and length-prefixed slices, null when they run out. */
    private class Bytes(val data: ByteArray, var at: Int) {
        val hasMore get() = at < data.size

        fun byte(): Int? = if (at < data.size) data[at++].toInt() and 0xFF else null

        fun varint32(): Long? = varint(32)

        fun varint(bits: Int): Long? {
            var result = 0L
            var shift = 0
            while (shift < bits) {
                val byte = byte() ?: return null
                result = result or ((byte and 0x7F).toLong() shl shift)
                if (byte and 0x80 == 0) return result
                shift += 7
            }
            return null
        }

        fun slice(): ByteArray? {
            val length = varint32() ?: return null
            if (at + length > data.size) return null
            return data.copyOfRange(at, at + length.toInt()).also { at += length.toInt() }
        }

        /** A block handle: offset and size. */
        fun handle(): Pair<Long, Long>? {
            val offset = varint(64) ?: return null
            val size = varint(64) ?: return null
            return offset to size
        }
    }
}

/** Snappy's raw format, enough to read a LevelDB block. */
internal object Snappy {
    fun decompress(data: ByteArray): ByteArray? {
        var at = 0
        fun byte(): Int? = if (at < data.size) data[at++].toInt() and 0xFF else null

        // The uncompressed length, a varint; only a hint here.
        var shift = 0
        while (true) {
            val b = byte() ?: return null
            if (b and 0x80 == 0) break
            shift += 7
            if (shift >= 32) return null
        }
        val output = ArrayList<Byte>()
        fun copy(length: Int, offset: Int): Boolean {
            if (offset <= 0) return false
            if (offset > output.size) return true
            val start = output.size - offset
            for (index in 0 until length) output += output[start + index % offset]
            return true
        }
        while (at < data.size) {
            val tag = byte() ?: break
            when (tag and 0x03) {
                0 -> {
                    var length = tag shr 2
                    if (length < 60) {
                        length += 1
                    } else {
                        var computed = 0
                        for (index in 0 until length - 59) computed = computed or ((byte() ?: return null) shl (8 * index))
                        length = computed + 1
                    }
                    if (length <= 0 || at + length > data.size) return null
                    for (index in 0 until length) output += data[at + index]
                    at += length
                }
                1 -> {
                    val low = byte() ?: return null
                    if (!copy(((tag shr 2) and 0x7) + 4, ((tag shr 5) shl 8) or low)) return null
                }
                2 -> {
                    val b0 = byte() ?: return null
                    val b1 = byte() ?: return null
                    if (!copy((tag shr 2) + 1, b0 or (b1 shl 8))) return null
                }
                else -> {
                    var offset = 0
                    for (index in 0 until 4) offset = offset or ((byte() ?: return null) shl (8 * index))
                    if (!copy((tag shr 2) + 1, offset)) return null
                }
            }
        }
        return output.toByteArray()
    }
}
