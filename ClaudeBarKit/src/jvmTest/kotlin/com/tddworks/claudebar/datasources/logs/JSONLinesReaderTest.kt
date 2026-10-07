package com.tddworks.claudebar.datasources.logs

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.io.RandomAccessFile
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.time.Instant
import java.util.UUID

/** `jsonLines`: one record per matching line, read incrementally — only what was appended since the last scan, the whole file when it changed under us. */
class JSONLinesReaderTest {
    companion object {
        internal val records = UsageLog.Records(
            files = "~/logs/*.jsonl",
            condition = UsageLog.Match("$.kind", JsonPrimitive("reply")),
            at = UsageLog.At.Field("$.at"),
            id = listOf("$.reply.id", "$.request"),
            model = "$.reply.model",
            tokens = UsageLog.Tokens(input = "$.reply.usage.in", output = "$.reply.usage.out",
                cacheWrite = "$.reply.usage.cacheIn", cacheWrite1h = "$.reply.usage.split.hour",
                cacheRead = "$.reply.usage.cacheHit"),
        )

        fun line(model: String, id: String = UUID.randomUUID().toString(), at: String = "2026-03-11T10:00:00.000Z") =
            """{"kind":"reply","request":"q_$id","reply":{"id":"r_$id","model":"$model","usage":{"in":10,"out":5}},"at":"$at"}"""

        /** A reply's usage sits under it; a side call's sits at the top. */
        internal val twoShapes = UsageLog.Records(files = "~/logs/*.jsonl", shapes = listOf(
            UsageLog.Shape(condition = UsageLog.Match("$.reply.role", JsonPrimitive("model")), at = UsageLog.At.Field("$.at"),
                tokens = UsageLog.Tokens(input = "$.reply.usage.in", output = "$.reply.usage.out"), cost = "$.reply.usage.usd"),
            UsageLog.Shape(condition = UsageLog.Match("$.kind", JsonPrimitive("side")), at = UsageLog.At.Field("$.at"),
                tokens = UsageLog.Tokens(input = "$.usage.in", output = "$.usage.out"), cost = "$.usage.usd"),
        ))
    }

    @TempDir
    lateinit var root: File

    private fun reader() = JSONLinesReader(records)

    private fun makeFile(content: String): String {
        val dir = File(root, UUID.randomUUID().toString()).apply { mkdirs() }
        return File(dir, "session.jsonl").apply { writeText(content) }.path
    }

    private fun append(content: String, path: String) = File(path).appendText(content)

    /** Replaces the file's bytes while keeping its inode, the way an in-place rewrite would. */
    private fun overwriteInPlace(content: String, path: String) = RandomAccessFile(path, "rw").use {
        it.setLength(0)
        it.write(content.encodeToByteArray())
    }

    // A line

    @Test
    fun `should count a usage line's model, tokens, identity and time`() {
        val line = """{"kind":"reply","request":"q_1","reply":{"id":"r_1","model":"m-large","usage":{"in":100,"out":50,"cacheIn":200,"cacheHit":30}},"at":"2026-03-11T10:30:45.123Z"}"""
        val records = reader().read(line)
        assertEquals(1, records.size)
        assertEquals("m-large", records[0].model)
        assertEquals(listOf(100L, 50L, 200L, 30L), listOf(records[0].input, records[0].output, records[0].cacheWrite, records[0].cacheRead))
        assertEquals(150L, records[0].tokens)
        assertEquals("r_1\u001Fq_1", records[0].id)
        assertEquals(Instant.parse("2026-03-11T10:30:45.123Z").toEpochMilli() / 1000.0, records[0].atSeconds)
    }

    @Test
    fun `should count only the lines the log's rule picks out`() {
        val content = """
        {"kind":"ask","reply":{"content":"hello"},"at":"2026-03-11T10:00:00.000Z"}
        ${line("m-large")}
        {"kind":"progress","data":{"kind":"hook"},"at":"2026-03-11T10:00:02.000Z"}
        """.trimIndent()
        assertEquals(listOf("m-large"), reader().read(content).map { it.model })
    }

    @Test
    fun `should count the hour-long cache writes beside all cache writes`() {
        val line = """{"kind":"reply","reply":{"model":"m-large","usage":{"cacheIn":200,"split":{"hour":150}}},"at":"2026-03-11T10:00:00.000Z"}"""
        val record = reader().read(line).first()
        assertEquals(200L, record.cacheWrite)
        assertEquals(150L, record.cacheWrite1h)
    }

    @Test
    fun `should count only the uncached input when the log's input includes the cache reads`() {
        val records = UsageLog.Records(
            files = "~/logs/*.jsonl", at = UsageLog.At.Field("$.at"),
            tokens = UsageLog.Tokens(input = "$.in", output = "$.out", cacheRead = "$.cached", inputIncludesCacheRead = true),
        )
        val record = JSONLinesReader(records).read("""{"in":100,"cached":70,"out":5,"at":"2026-03-11T10:00:00.000Z"}""").first()
        assertEquals(30L, record.input)
        assertEquals(70L, record.cacheRead)
        assertEquals(35L, record.tokens)
    }

    @Test
    fun `should count zero for a kind of token a line doesn't mention`() {
        val records = reader().read(line("m-large"))
        assertEquals(0L, records[0].cacheWrite)
        assertEquals(0L, records[0].cacheRead)
    }

    @Test
    fun `should not count a line that says nothing about usage`() {
        assertTrue(reader().read("""{"kind":"reply","reply":{"model":"m-large"},"at":"2026-03-11T10:00:00.000Z"}""").isEmpty())
    }

    @Test
    fun `should not count a line without a time or the model the log's rule asks for`() {
        val noTime = """{"kind":"reply","reply":{"model":"m-large","usage":{"in":1}}}"""
        val noModel = """{"kind":"reply","reply":{"usage":{"in":1}},"at":"2026-03-11T10:00:00.000Z"}"""
        assertTrue(reader().read(noTime + "\n" + noModel).isEmpty())
    }

    @Test
    fun `should count the good lines and pass over broken ones`() {
        assertEquals(1, reader().read("not json at all\n${line("m-large")}\n{\"incomplete\": true").size)
    }

    @Test
    fun `should give a line no identity when part of it is missing`() {
        val line = """{"kind":"reply","reply":{"model":"m-large","usage":{"in":10}},"at":"2026-03-11T10:00:00.000Z"}"""
        assertNull(reader().read(line).first().id)
    }

    @Test
    fun `should not pick out a line whose text merely quotes the rule's value`() {
        val content = """{"kind":"ask","reply":{"content":"the \"reply\" kind"},"at":"2026-03-11T10:00:00.000Z"}"""
        assertTrue(reader().read(content).isEmpty())
    }

    // A log that writes a record two ways

    @Test
    fun `should count a line of either shape`() {
        val content = """
        {"kind":"turn","reply":{"role":"model","usage":{"in":100,"out":50,"usd":0.5}},"at":"2026-03-11T10:00:00.000Z"}
        {"kind":"side","usage":{"in":7,"out":3,"usd":0.01},"at":"2026-03-11T10:00:01.000Z"}
        """.trimIndent()
        val records = JSONLinesReader(twoShapes).read(content)

        assertEquals(listOf(100L, 7L), records.map { it.input })
        assertEquals(listOf(50L, 3L), records.map { it.output })
        assertEquals(listOf(NanoAmount.parse("0.5"), NanoAmount.parse("0.01")), records.map { it.cost })
    }

    @Test
    fun `should pass over a line no shape picks out`() {
        val content = """
        {"kind":"turn","reply":{"role":"person","usage":{"in":100}},"at":"2026-03-11T10:00:00.000Z"}
        {"kind":"rollup","of":"side","usage":{"in":999},"at":"2026-03-11T10:00:01.000Z"}
        """.trimIndent()
        assertTrue(JSONLinesReader(twoShapes).read(content).isEmpty())
    }

    @Test
    fun `should read a line by the first shape whose where holds, and by that shape alone`() {
        val line = """{"kind":"side","reply":{"role":"model","usage":{"in":100,"out":50}},"usage":{"in":7,"out":3,"usd":0.01},"at":"2026-03-11T10:00:00.000Z"}"""
        val record = JSONLinesReader(twoShapes).read(line).first()

        assertEquals(100L, record.input)
        assertEquals(50L, record.output)
        assertNull(record.cost)
    }

    // A file, from an offset

    @Test
    fun `should count the lines after where it stopped, holding back a half-written last line`() {
        val first = line("m-small")
        val second = line("m-large")
        val unterminated = line("m-tiny")
        val path = makeFile("$first\n$second\n$unterminated")

        val chunk = reader().read(path, (first.encodeToByteArray().size + 1).toLong())

        assertEquals(listOf("m-large"), chunk.records.map { it.model })
        assertEquals((first.encodeToByteArray().size + second.encodeToByteArray().size + 2).toLong(), chunk.endOffset)
        // The unterminated line still counts, but is left for the next read to finish.
        assertEquals(listOf("m-tiny"), chunk.tail.map { it.model })
    }

    @Test
    fun `should count a very long line and the lines after it`() {
        val padding = "x".repeat(3 * 1024 * 1024)
        val long = """{"kind":"reply","reply":{"model":"m-large","content":"$padding","usage":{"in":1,"out":1}},"at":"2026-03-11T10:00:00.000Z"}"""
        val path = makeFile("$long\n${line("m-small")}\n")

        val chunk = reader().read(path, 0)

        assertEquals(listOf("m-large", "m-small"), chunk.records.map { it.model })
        assertTrue(chunk.tail.isEmpty())
    }

    // Between scans

    @Test
    fun `should count an unchanged log again without rereading it`() = runTest {
        val path = makeFile(line("m-large") + "\n")
        val reader = reader()

        reader.records(listOf(path))
        val records = reader.records(listOf(path))

        assertEquals(listOf("m-large"), records.map { it.model })
        assertEquals(JSONLinesReader.ScanSummary(reused = 1, extended = 0, reparsed = 0), reader.lastScan())
    }

    @Test
    fun `should read only the lines added to a log since it last looked`() = runTest {
        val path = makeFile(line("m-large") + "\n")
        val reader = reader()

        reader.records(listOf(path))
        append(line("m-small") + "\n", path)
        val records = reader.records(listOf(path))

        assertEquals(listOf("m-large", "m-small"), records.map { it.model })
        assertEquals(JSONLinesReader.ScanSummary(reused = 0, extended = 1, reparsed = 0), reader.lastScan())
    }

    @Test
    fun `should count a line once it is finished that was half written when it last looked`() = runTest {
        val small = line("m-small")
        val path = makeFile(line("m-large") + "\n" + small.substring(0, 40))
        val reader = reader()

        val before = reader.records(listOf(path))
        append(small.substring(40) + "\n", path)
        val after = reader.records(listOf(path))

        assertEquals(listOf("m-large"), before.map { it.model })
        assertEquals(listOf("m-large", "m-small"), after.map { it.model })
    }

    @Test
    fun `should count an unended last line once when more is added after it`() = runTest {
        // Records without an identity are never deduplicated later, so a tail line counted
        // twice would inflate the totals.
        val bare = """{"kind":"reply","reply":{"model":"m-small","usage":{"in":10,"out":5}},"at":"2026-03-11T10:00:00.000Z"}"""
        val path = makeFile(line("m-large") + "\n" + bare)
        val reader = reader()

        val before = reader.records(listOf(path))
        append("\n" + line("m-tiny") + "\n", path)
        val after = reader.records(listOf(path))

        assertEquals(listOf("m-large", "m-small"), before.map { it.model })
        assertEquals(listOf("m-large", "m-small", "m-tiny"), after.map { it.model })
    }

    @Test
    fun `should reread a log rewritten in place`() = runTest {
        val path = makeFile(line("m-large") + "\n")
        val reader = reader()

        reader.records(listOf(path))
        overwriteInPlace(line("m-small") + "\n" + line("m-tiny") + "\n", path)
        val records = reader.records(listOf(path))

        assertEquals(listOf("m-small", "m-tiny"), records.map { it.model })
        assertEquals(JSONLinesReader.ScanSummary(reused = 0, extended = 0, reparsed = 1), reader.lastScan())
    }

    @Test
    fun `should reread a log that shrank`() = runTest {
        val path = makeFile(line("m-large") + "\n" + line("m-small") + "\n")
        val reader = reader()

        reader.records(listOf(path))
        overwriteInPlace(line("m-tiny") + "\n", path)

        assertEquals(listOf("m-tiny"), reader.records(listOf(path)).map { it.model })
    }

    @Test
    fun `should reread a log replaced by a new file`() = runTest {
        val path = makeFile(line("m-large") + "\n")
        val reader = reader()

        reader.records(listOf(path))
        // An atomic write lands as a new file (new inode) at the same path.
        val replacement = File(File(path).parentFile, "replacement.tmp").apply { writeText(line("m-large") + "\n" + line("m-small") + "\n") }
        Files.move(replacement.toPath(), File(path).toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
        val records = reader.records(listOf(path))

        assertEquals(listOf("m-large", "m-small"), records.map { it.model })
        assertEquals(JSONLinesReader.ScanSummary(reused = 0, extended = 0, reparsed = 1), reader.lastScan())
    }

    @Test
    fun `should forget a log once it is no longer looked at`() = runTest {
        val kept = makeFile(line("m-large") + "\n")
        val dropped = makeFile(line("m-small") + "\n")
        val reader = reader()

        reader.records(listOf(kept, dropped))
        val records = reader.records(listOf(kept))

        assertEquals(listOf("m-large"), records.map { it.model })
        assertEquals(1, reader.cachedFileCount())
    }
}
