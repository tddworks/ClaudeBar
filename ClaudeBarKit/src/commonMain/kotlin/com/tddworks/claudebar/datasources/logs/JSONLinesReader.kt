package com.tddworks.claudebar.datasources.logs

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.io.Buffer
import kotlinx.io.Source
import kotlinx.io.buffered
import kotlinx.io.indexOf
import kotlinx.io.readByteArray

/**
 * `jsonLines` — one JSON object per line, in files a tool appends to.
 *
 * Keeps the records read from each file between scans, so a scan reads only what changed:
 * nothing for an untouched file, the appended lines for a growing one, and the whole file
 * otherwise.
 *
 * Appending is inferred from file metadata plus a hash of the bytes around the already-read
 * prefix; it is not proven. Anything that fails these checks (a new inode, a shrink, coarse
 * timestamps, changed head or tail bytes) is read again from the start.
 *
 * Scans hold a lock, so overlapping ones run one after another and the later one finds the
 * earlier one's work already kept.
 */
internal class JSONLinesReader(records: UsageLog.Records) {
    /** What the last scan did with each file it was given. */
    data class ScanSummary(val reused: Int = 0, val extended: Int = 0, val reparsed: Int = 0)

    /** Records read from part of a file: the complete lines from the starting offset on, and any final line still missing its newline. */
    data class Chunk(
        /** Records from lines that end in a newline. */
        val records: List<LogRecord>,
        /** Byte offset just past the last complete line; the next read resumes here. */
        val endOffset: Long,
        /** Records from a final line with no newline yet: the tool may still be writing it, so the next read parses it again. */
        val tail: List<LogRecord>,
    )

    private class Entry(
        val stamp: FileStamp,
        val endOffset: Long,
        val prefixGuard: Long,
        val records: List<LogRecord>,
        val tail: List<LogRecord>,
    )

    private val shapes = records.shapes.map(::RecordShape)

    /** A line must hold one of these before it is decoded; null reads every line. */
    private val fragments = shapes.fragments
    private val lock = Mutex()
    private var entries: Map<String, Entry> = emptyMap()
    private var scan = ScanSummary()

    suspend fun lastScan(): ScanSummary = lock.withLock { scan }

    suspend fun cachedFileCount(): Int = lock.withLock { entries.size }

    /** Records from [files], in file order and line order within each file. Files not in [files] are forgotten; unreadable ones are skipped. */
    suspend fun records(files: List<String>): List<LogRecord> = lock.withLock {
        var summary = ScanSummary()
        val kept = mutableMapOf<String, Entry>()
        val records = mutableListOf<LogRecord>()
        for (path in files) {
            val (entry, change) = refreshedEntry(path) ?: continue
            summary = when (change) {
                Change.REUSED -> summary.copy(reused = summary.reused + 1)
                Change.EXTENDED -> summary.copy(extended = summary.extended + 1)
                Change.REPARSED -> summary.copy(reparsed = summary.reparsed + 1)
            }
            kept[path] = entry
            records += entry.records
            records += entry.tail
        }
        entries = kept
        scan = summary
        records
    }

    // Reading a file

    /** Reads a file from [offset] to its end, streaming it rather than loading it whole. */
    fun read(path: String, offset: Long): Chunk = fileSource(path, offset).buffered().use { source ->
        val records = mutableListOf<LogRecord>()
        var endOffset = offset
        while (true) {
            val newline = source.indexOf(NEWLINE)
            if (newline < 0) break
            parseLine(source.readByteArray(newline.toInt()))?.let { records += it }
            source.skip(1)
            endOffset += newline + 1
        }
        Chunk(records, endOffset, parseTail(source.readByteArray()))
    }

    /** Records in [content], every line, the last one with or without its newline. */
    fun read(content: String): List<LogRecord> {
        val source: Source = Buffer().apply { write(content.encodeToByteArray()) }
        val records = mutableListOf<LogRecord>()
        while (true) {
            val newline = source.indexOf(NEWLINE)
            if (newline < 0) break
            parseLine(source.readByteArray(newline.toInt()))?.let { records += it }
            source.skip(1)
        }
        return records + parseTail(source.readByteArray())
    }

    private fun parseTail(bytes: ByteArray): List<LogRecord> = listOfNotNull(parseLine(bytes))

    /** The record on one line, or null when it holds none of the shapes' fragments, isn't JSON, or isn't a record. */
    private fun parseLine(line: ByteArray): LogRecord? {
        if (fragments != null && fragments.none { line.contains(it) }) return null
        val json = jsonDocument(line) ?: return null
        return shapes.record(json)
    }

    // Keeping what was read

    private enum class Change { REUSED, EXTENDED, REPARSED }

    private fun refreshedEntry(path: String): Pair<Entry, Change>? {
        // Stamp first: lines written while reading then show up as a change next scan.
        val stamp = fileStamp(path) ?: return null
        val previous = entries[path]
        if (previous != null && previous.stamp.isStrong && stamp.isStrong && previous.stamp.inode == stamp.inode) {
            if (previous.stamp == stamp) return previous to Change.REUSED
            if (stamp.size > previous.stamp.size && prefixGuard(path, previous.endOffset) == previous.prefixGuard) {
                val chunk = runCatching { read(path, previous.endOffset) }.getOrNull()
                val guard = chunk?.let { prefixGuard(path, it.endOffset) }
                if (chunk != null && guard != null) {
                    return Entry(stamp, chunk.endOffset, guard, previous.records + chunk.records, chunk.tail) to Change.EXTENDED
                }
            }
        }
        val chunk = runCatching { read(path, 0) }.getOrNull() ?: return null
        val guard = prefixGuard(path, chunk.endOffset) ?: return null
        return Entry(stamp, chunk.endOffset, guard, chunk.records, chunk.tail) to Change.REPARSED
    }

    /**
     * A hash of the first and last [GUARD_BYTES] of the file's first [length] bytes. A bounded
     * spot check, not a proof: it catches truncate-and-rewrite and changed edges, but not a
     * same-length edit in the middle of a prefix over 128 KB, which the append-only assumption
     * above rules out.
     */
    private fun prefixGuard(path: String, length: Long): Long? = runCatching {
        val headLength = minOf(length, GUARD_BYTES)
        val tailStart = maxOf(headLength, length - minOf(length, GUARD_BYTES))
        var hash = FNV_OFFSET
        fun combine(byte: Byte) {
            hash = (hash xor (byte.toLong() and 0xff)) * FNV_PRIME
        }
        repeat(8) { combine((length ushr (it * 8)).toByte()) }
        fileSource(path, 0).buffered().use { head -> head.readUpTo(headLength).forEach(::combine) }
        combine(0x1f)
        fileSource(path, tailStart).buffered().use { tail -> tail.readUpTo(length - tailStart).forEach(::combine) }
        hash
    }.getOrNull()

    private fun Source.readUpTo(count: Long): ByteArray {
        val out = Buffer()
        while (out.size < count) {
            if (readAtMostTo(out, count - out.size) <= 0) break
        }
        return out.readByteArray()
    }

    private fun ByteArray.contains(fragment: ByteArray): Boolean {
        if (fragment.isEmpty()) return true
        val first = fragment[0]
        val last = size - fragment.size
        var start = 0
        while (start <= last) {
            if (this[start] == first) {
                var matched = 1
                while (matched < fragment.size && this[start + matched] == fragment[matched]) matched++
                if (matched == fragment.size) return true
            }
            start++
        }
        return false
    }

    private companion object {
        const val NEWLINE: Byte = '\n'.code.toByte()
        const val GUARD_BYTES = 64L * 1024
        const val FNV_OFFSET = -0x340d631b7bdddcdbL
        const val FNV_PRIME = 0x100000001b3L
    }
}
