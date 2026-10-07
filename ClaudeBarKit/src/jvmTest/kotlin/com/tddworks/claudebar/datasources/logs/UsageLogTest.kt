package com.tddworks.claudebar.datasources.logs

import com.tddworks.claudebar.datasources.DefinitionError
import com.tddworks.claudebar.quotas.DailyUsageStat
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlin.math.roundToLong

/** A usage log, end to end: the files its glob names, read into records, deduplicated, priced and summed into one stat per local day. */
class UsageLogTest {
    companion object {
        internal val definition = UsageLog.Definition(
            records = UsageLog.Records(
                files = "~/.acme/sessions/**/*.jsonl",
                condition = UsageLog.Match("$.kind", JsonPrimitive("reply")),
                at = UsageLog.At.Field("$.at"),
                id = listOf("$.reply.id", "$.request"),
                model = "$.reply.model",
                tokens = UsageLog.Tokens(input = "$.reply.usage.in", output = "$.reply.usage.out",
                    cacheWrite = "$.reply.usage.cacheIn", cacheRead = "$.reply.usage.cacheHit"),
            ),
            prices = UsageLog.Prices(file = "acme-prices.json"),
            freeWhen = UsageLog.FreeWhen(UsageLog.LocalEndpointRule(file = "~/.acme/config.json", url = listOf(listOf("$.baseURL")))),
            sessionGap = 1800.0,
        )

        /** A log that writes a record two ways: a reply's usage under it, a side call's at the top. */
        val twoShapes = """
        { "records": { "files": "~/x/*.jsonl",
                       "shapes": [{ "where": { "path": "$.kind", "equals": "reply" }, "at": "$.at", "tokens": { "total": "$.reply.n" } },
                                  { "where": { "path": "$.kind", "equals": "side" }, "at": "$.at", "tokens": { "total": "$.n" } }] } }
        """.trimIndent()

        fun nanos(usd: String) = NanoAmount.parse(usd)!!.rounded()
    }

    @TempDir
    lateinit var home: File

    private val calendar = localCalendar()
    private val now = System.currentTimeMillis() / 1000.0

    private fun log(definition: UsageLog.Definition = Companion.definition) = UsageLog.make(
        definition, home = home.path, environment = { null },
        scripts = { if (it == "acme-prices.json") PriceListTest.file else null }, calendar = calendar, now = { now },
    )

    private fun write(lines: List<String>, name: String = "project/one.jsonl") {
        val file = File(home, ".acme/sessions/$name")
        file.parentFile.mkdirs()
        file.writeText(lines.joinToString("\n"))
    }

    private fun iso(seconds: Double) = Instant.ofEpochMilli((seconds * 1000).roundToLong()).toString()

    private fun stamp(offset: Double = 0.0, daysAgo: Int = 0): String {
        val day = calendar.addingDays(-daysAgo, now)
        return iso(if (daysAgo == 0) day + offset else calendar.startOfDay(day) + 43_200 + offset)
    }

    private fun line(model: String = "m-medium-2", id: String? = null, input: Int = 1000, output: Int = 500, cacheRead: Int = 0, at: String): String {
        val identity = id?.let { """"request":"q_$it","reply":{"id":"r_$it",""" } ?: """"reply":{"""
        return """{"kind":"reply",$identity"model":"$model","usage":{"in":$input,"out":$output,"cacheHit":$cacheRead}},"at":"$at"}"""
    }

    private suspend fun today(): DailyUsageStat = log().days(last = 1)[0]

    @Test
    fun `should show every day of the range, a day with no usage as empty`() = runTest {
        write(listOf(line(at = stamp())))
        val days = log().days(last = 3)
        assertEquals(3, days.size)
        assertEquals(DateRange.last(3, now, calendar).days(calendar), days.map { it.dateSeconds })
        assertTrue(days[0].isEmpty && days[1].isEmpty)
        assertEquals(1500L, days[2].totalTokens)
    }

    @Test
    fun `should count usage on the day it happened`() = runTest {
        write(listOf(line(at = stamp()), line(input = 2000, output = 1000, at = stamp(daysAgo = 1))))
        val days = log().days(last = 2)
        assertEquals(1500L, days[1].totalTokens)
        assertEquals(3000L, days[0].totalTokens)
    }

    @Test
    fun `should show every day empty when nothing is logged`() = runTest {
        assertTrue(log().days(last = 2).all { it.isEmpty })
    }

    @Test
    fun `should count logs in folders at any depth, and only the files that match`() = runTest {
        write(listOf(line(at = stamp())), "a/b/c/deep.jsonl")
        write(listOf(line(at = stamp())), "notes.txt")
        assertEquals(1500L, today().totalTokens)
    }

    // Written twice, counted once

    @Test
    fun `should count usage written twice in a log once`() = runTest {
        val copy = line(id = "1", at = stamp())
        write(listOf(copy, copy, copy))
        assertEquals(1500L, today().totalTokens)
    }

    @Test
    fun `should count the last copy of usage written more than once`() = runTest {
        write(listOf(line(id = "1", output = 1, at = stamp()), line(id = "1", output = 1, at = stamp(0.1)), line(id = "1", output = 500, at = stamp(0.9))))
        val today = today()
        assertEquals(500L, today.outputTokens)
        assertEquals(1500L, today.totalTokens)
    }

    @Test
    fun `should count usage copied into another log once`() = runTest {
        write(listOf(line(id = "1", at = stamp())), "p/one.jsonl")
        write(listOf(line(id = "1", at = stamp())), "p/two.jsonl")
        assertEquals(1500L, today().totalTokens)
    }

    @Test
    fun `should count every distinct entry, and every entry without an identity`() = runTest {
        write(listOf(line(id = "1", at = stamp()), line(id = "2", input = 2000, output = 1000, at = stamp()), line(at = stamp()), line(at = stamp())))
        assertEquals(7500L, today().totalTokens)
    }

    // Prices

    @Test
    fun `should show the day's cost and cache savings from the price list`() = runTest {
        write(listOf(line(input = 1000, output = 500, cacheRead = 1_000_000, at = stamp())))
        val today = today()
        assertEquals(1_000_000L, today.cacheReadTokens)
        assertEquals(nanos("2.7"), today.cachedSavingsNanos)
        assertEquals(nanos("0.3105"), today.totalCostNanos)
    }

    @Test
    fun `should show the cost the log gives over any price, with each entry its own session`() = runTest {
        val definition = UsageLog.Definition(
            records = UsageLog.Records(files = "~/.acme/sessions/**/*.jsonl", at = UsageLog.At.Field("$.at"),
                tokens = UsageLog.Tokens(total = "$.tokens"), cost = "$.cost"),
            prices = UsageLog.Prices(file = "acme-prices.json"),
        )
        write(listOf("""{"at":"${stamp()}","tokens":1234,"cost":0.0123}"""))
        val today = log(definition).days(last = 1)[0]
        assertEquals(nanos("0.0123"), today.totalCostNanos)
        assertEquals(1234L, today.totalTokens)
        // Without a session gap, each record is a session and no working time is known.
        assertEquals(1L, today.sessionCount)
        assertEquals(0.0, today.workingTime)
    }

    // A local route

    private fun route(url: String) {
        val config = File(home, ".acme/config.json")
        config.parentFile.mkdirs()
        config.writeText("""{"baseURL":"$url"}""")
    }

    @Test
    fun `should cost nothing today for an unlisted model when the tool runs on this Mac`() = runTest {
        route("http://localhost:11434")
        write(listOf(line(model = "acme-internal-7b", at = stamp())))
        assertEquals(0L, today().totalCostNanos)
    }

    @Test
    fun `should estimate an unlisted model's cost when the tool runs on a remote gateway`() = runTest {
        route("https://gateway.example.com")
        write(listOf(line(model = "acme-internal-7b", at = stamp())))
        assertEquals(nanos("0.0105"), today().totalCostNanos)
    }

    @Test
    fun `should keep an earlier day's cost when the tool runs on this Mac only now`() = runTest {
        route("http://localhost:11434")
        write(listOf(line(model = "acme-internal-7b", at = stamp(daysAgo = 1))))
        val days = log().days(last = 2)
        assertTrue(days[1].isEmpty)
        assertEquals(nanos("0.0105"), days[0].totalCostNanos)
    }

    // Sessions

    @Test
    fun `should start another session after a long pause and count working time within each`() = runTest {
        val start = calendar.startOfDay(now) + 60
        if (now - start <= 3 * 3600) return@runTest // too early in the day to fit three hours
        fun at(minutes: Double) = iso(start + minutes * 60)
        write(listOf(line(at = at(0.0)), line(at = at(10.0)), line(at = at(120.0)), line(at = at(125.0))))
        val today = today()
        assertEquals(2L, today.sessionCount)
        assertEquals(15.0 * 60, today.workingTime)
    }

    @Test
    fun `should count lines added to a log since last time once each`() = runTest {
        write(listOf(line(id = "1", at = stamp())))
        val log = log()
        val before = log.days(last = 1)[0]
        write(listOf(line(id = "1", at = stamp()), line(id = "2", input = 2000, output = 1000, at = stamp())))
        val after = log.days(last = 1)[0]
        assertEquals(1500L, before.totalTokens)
        assertEquals(4500L, after.totalTokens)
    }

    // The definition

    @Test
    fun `should read a usage history definition with its defaults, and keep it when written out and read back`() {
        val json = """
        { "records": { "files": "~/x/*.jsonl", "at": "$.at", "tokens": { "total": "$.n" } },
          "freeWhen": { "localEndpoint": { "file": "~/x.json", "url": ["$.a", ["$.b", "$.c"]] } } }
        """.trimIndent()
        val definition = UsageLog.Definition.from(Json.parseToJsonElement(json))
        assertEquals(UsageLog.Format.JSON_LINES, definition.records.format)
        assertEquals(listOf(emptyList<String>()), definition.records.shapes.map { it.id })
        assertEquals(listOf(listOf("$.a"), listOf("$.b", "$.c")), definition.freeWhen?.localEndpoint?.url)
        assertEquals(definition, UsageLog.Definition.from(definition.toJson()))
    }

    @Test
    fun `should read other apps in a usage history with their label and own records, and no prices`() {
        val json = """
        { "records": { "files": "~/x/*.jsonl", "at": "$.at", "tokens": { "total": "$.n" } },
          "otherApps": [{ "label": "Desk", "records": { "files": "~/desk.json", "format": "json",
                          "at": { "field": "$.day", "format": "yyyy-MM-dd" }, "tokens": { "total": "$.n" } } }] }
        """.trimIndent()
        val definition = UsageLog.Definition.from(Json.parseToJsonElement(json))
        val app = definition.otherApps!!.first()
        assertEquals("Desk", app.label)
        assertEquals(listOf(UsageLog.At.Formatted(field = "$.day", format = "yyyy-MM-dd")), app.definition.records.shapes.map { it.at })
        assertNull(app.definition.prices)
        assertNull(app.definition.otherApps)
        assertEquals(definition, UsageLog.Definition.from(definition.toJson()))
    }

    @Test
    fun `should keep the login's own usage history unchanged when other apps are added`() {
        val app = UsageLog.OtherApp(label = "Desk", records = UsageLog.Records(files = "~/desk.json", format = UsageLog.Format.JSON, at = UsageLog.At.Field("$.at")))
        assertEquals(log().fingerprint, log(definition.copy(otherApps = listOf(app))).fingerprint)
    }

    @Test
    fun `should keep a log's shapes when an added login's patch moves its files`() {
        val definition = UsageLog.Definition.from(Json.parseToJsonElement(twoShapes))
        val patch = JsonObject(mapOf("records" to JsonObject(mapOf("files" to JsonPrimitive("{{account.dir}}/*.jsonl")))))

        val moved = definition.patched(patch).filled(mapOf("dir" to "/tmp/work"), scope = "account")

        assertEquals("/tmp/work/*.jsonl", moved.records.files)
        assertEquals(definition.records.shapes, moved.records.shapes)
        assertEquals(2, moved.records.shapes.size)
    }

    @Test
    fun `should refuse a log that gives a record's fields beside its shapes`() {
        val json = twoShapes.replace(""""files": "~/x/*.jsonl",""", """"files": "~/x/*.jsonl", "at": "$.at",""")
        assertThrows(DefinitionError::class.java) { UsageLog.Definition.from(Json.parseToJsonElement(json)) }
    }

    @Test
    fun `should refuse a shape in a list that has no where`() {
        val json = twoShapes.replace(""""where": { "path": "$.kind", "equals": "side" }, """, "")
        assertThrows(DefinitionError::class.java) { UsageLog.Definition.from(Json.parseToJsonElement(json)) }
    }

    @Test
    fun `should count an app's daily total on the day it names, with no cost known`() = runTest {
        val app = UsageLog.OtherApp(label = "Desk", records = UsageLog.Records(
            files = "~/desk/today.json", format = UsageLog.Format.JSON,
            at = UsageLog.At.Formatted(field = "$.day", format = "yyyy-MM-dd"), tokens = UsageLog.Tokens(total = "$.n"),
        ))
        val file = File(home, "desk/today.json")
        file.parentFile.mkdirs()
        val yesterday = DateTimeFormatter.ofPattern("yyyy-MM-dd").withZone(ZoneId.systemDefault())
            .format(Instant.ofEpochMilli((calendar.addingDays(-1, now) * 1000).roundToLong()))
        file.writeText("""{"day":"$yesterday","n":74422}""")

        val days = log(app.definition).days(last = 2)

        assertEquals(listOf(74422L, 0L), days.map { it.totalTokens })
        assertFalse(log(app.definition).knowsCost)
    }
}
