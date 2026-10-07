package com.tddworks.claudebar.datasources.logs

import com.tddworks.claudebar.datasources.DefinitionJson
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource
import java.io.File
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/** `json`: one document per file, one record; the time may come from the file's path. */
class JSONLogReaderTest {
    @TempDir
    lateinit var dir: File

    private fun file(name: String, content: String): String {
        val file = File(dir, name)
        file.parentFile.mkdirs()
        file.writeText(content)
        return file.path
    }

    private val rule = UsageLog.At.FromPath(pattern = """run-(\d{8}T\d{4})""", format = "yyyyMMdd'T'HHmm", timeZone = "UTC")

    private fun reader(at: UsageLog.At) = JSONLogReader(
        UsageLog.Records(files = "~/runs/*/summary.json", format = UsageLog.Format.JSON, at = at,
            tokens = UsageLog.Tokens(total = "$.used"), cost = "$.spent"),
    )

    private fun seconds(iso: String) = Instant.parse(iso).epochSecond.toDouble()

    private fun at(json: String): UsageLog.At = DefinitionJson.decodeFromJsonElement(Json.parseToJsonElement(json))

    @Test
    fun `should count a summary file as one record, timed by its path in the rule's time zone`() {
        val path = file("run-20261003T2330/summary.json", """{"used":1200,"spent":"0.75"}""")
        val records = reader(rule).records(listOf(path))
        assertEquals(1, records.size)
        assertEquals(1200L, records[0].tokens)
        assertEquals(NanoAmount.parse("0.75"), records[0].cost)
        assertEquals(seconds("2026-10-03T23:30:00Z"), records[0].atSeconds)
    }

    @Test
    fun `should not count a file whose path carries no time, that is broken, or that says nothing about usage`() {
        val noTime = file("other/summary.json", """{"used":1}""")
        val broken = file("run-20261003T0100/summary.json", "{ nope")
        val empty = file("run-20261003T0200/summary.json", """{"title":"x"}""")
        assertTrue(reader(rule).records(listOf(noTime, broken, empty)).isEmpty())
    }

    @Test
    fun `should time a summary file by a field inside it when the rule says so`() {
        val path = file("a/summary.json", """{"when":"2026-10-03T08:00:00Z","used":5}""")
        assertEquals(seconds("2026-10-03T08:00:00Z"), reader(UsageLog.At.Field("$.when")).records(listOf(path)).first().atSeconds)
    }

    @ParameterizedTest
    @ValueSource(strings = ["America/Los_Angeles", "Asia/Shanghai"])
    fun `should time a written-out date in the rule's time zone, or this Mac's when it names none`(zone: String) {
        val path = file("desk/today.json", """{"day":"2026-05-28","used":74422}""")
        val local = UsageLog.At.Formatted(field = "$.day", format = "yyyy-MM-dd")
        val named = UsageLog.At.Formatted(field = "$.day", format = "yyyy-MM-dd", timeZone = zone)
        val day = LocalDate.of(2026, 5, 28)

        assertEquals(day.atStartOfDay(ZoneId.of(zone)).toEpochSecond().toDouble(), reader(named).records(listOf(path)).first().atSeconds)
        assertEquals(day.atStartOfDay(ZoneId.systemDefault()).toEpochSecond().toDouble(), reader(local).records(listOf(path)).first().atSeconds)
    }

    @ParameterizedTest
    @ValueSource(strings = ["2026-02-30", "May 28 2026", "2026-05-28T08:00:00Z"])
    fun `should not count a file whose date doesn't fit the rule's format`(text: String) {
        val path = file("desk/today.json", """{"day":"$text","used":5}""")
        assertTrue(reader(UsageLog.At.Formatted(field = "$.day", format = "yyyy-MM-dd")).records(listOf(path)).isEmpty())
    }

    @ParameterizedTest
    @ValueSource(strings = ["-5", "74422.5", "\"lots\""])
    fun `should not count a file whose token count isn't a whole, positive number`(count: String) {
        val path = file("a/summary.json", """{"when":"2026-10-03T08:00:00Z","used":$count}""")
        assertTrue(reader(UsageLog.At.Field("$.when")).records(listOf(path)).isEmpty())
    }

    @Test
    fun `should keep a dated-field time rule when the definition is written out and read back`() {
        val formatted = at("""{"field":"$.day","format":"yyyy-MM-dd"}""")
        assertEquals(UsageLog.At.Formatted(field = "$.day", format = "yyyy-MM-dd"), formatted)
        assertEquals(formatted, DefinitionJson.decodeFromJsonElement<UsageLog.At>(DefinitionJson.encodeToJsonElement(formatted)))
    }

    @Test
    fun `should read a time rule given as a field or as a path pattern, and keep it when written out and read back`() {
        val field = at("\"$.ts\"")
        val path = at("""{"fromPath":"x_(\\d+)","format":"yyyyMMdd","timeZone":"UTC"}""")
        assertEquals(UsageLog.At.Field("$.ts"), field)
        assertEquals(UsageLog.At.FromPath(pattern = """x_(\d+)""", format = "yyyyMMdd", timeZone = "UTC"), path)
        assertEquals(path, DefinitionJson.decodeFromJsonElement<UsageLog.At>(DefinitionJson.encodeToJsonElement(path)))
    }
}
