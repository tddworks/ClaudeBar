package com.tddworks.claudebar.datasources.logs

import com.tddworks.claudebar.datasources.DefinitionJson
import com.tddworks.claudebar.datasources.JsonPath
import com.tddworks.claudebar.datasources.JsonScope
import com.tddworks.claudebar.datasources.Paths
import com.tddworks.claudebar.datasources.Placeholders
import com.tddworks.claudebar.datasources.decoding
import com.tddworks.claudebar.datasources.mapStrings
import com.tddworks.claudebar.datasources.merged
import com.tddworks.claudebar.diagnostics.AppLog
import com.tddworks.claudebar.quotas.DailyUsageStat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.IO
import kotlinx.coroutines.withContext
import kotlinx.serialization.EncodeDefault
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.encodeToJsonElement
import org.kotlincrypto.hash.sha2.SHA256

/**
 * HOW TO EXTRACT A LOGIN'S USAGE HISTORY — the one part that differs per provider. Built from
 * a definition's `usageHistory` block, filled with the login's values: where its tool's logs
 * are, how a record reads, what a token costs. [days] reads and prices them into one stat
 * per day (docs/features/daily-usage/design.md).
 *
 * Every reader yields the same record, so deduplication, days, sessions and prices never
 * learn which tool wrote the log.
 */
internal class UsageLog(
    val definition: Definition,
    private val reader: LogReader,
    private val prices: PriceList?,
    private val localEndpoint: LocalEndpoint?,
    private val files: String,
    /** The local calendar its days are counted in. */
    val calendar: LocalCalendar,
    private val now: () -> Double,
    /**
     * Changes whenever how the logs read does — the definition, the price file, where the
     * files are — so days kept under an older one are summed again.
     */
    val fingerprint: String,
) {
    /** The start of the day that holds now. */
    val todaySeconds: Double get() = calendar.startOfDay(now())

    /** Now, as this log's clock tells it. */
    val currentTimeSeconds: Double get() = now()

    /**
     * Whether these logs can say what a day cost: a price list, or a cost every shape of the
     * log writes itself. Without either every cost reads zero.
     */
    val knowsCost: Boolean get() = prices != null || definition.records.shapes.all { it.cost != null }

    /** One stat per day of [range], every date present; a day with nothing is an empty day. Unreadable files are skipped. */
    suspend fun days(range: DateRange): List<DailyUsageStat> = withContext(Dispatchers.IO) {
        val found = LogFileFinder.files(files, changedSinceSeconds = range.firstSeconds)
        val raw = reader.records(found)
        val scan = reader.lastScan()
        AppLog.probes.info(
            "Usage history: scanned ${found.size} recent log files (${scan.reused} unchanged, " +
                "${scan.extended} appended, ${scan.reparsed} read in full)",
        )
        val records = LogRecord.deduplicated(raw)
        AppLog.probes.info("Usage history: ${raw.size} raw records, ${records.size} after dedup")

        // `freeWhen` describes the route now, so it prices only the day that holds now:
        // an earlier day keeps its estimate.
        val today = calendar.startOfDay(now())
        val freeDay = today.takeIf { range.contains(it, calendar) && localEndpoint?.isLocal() == true }
        if (freeDay != null) {
            AppLog.probes.debug("Usage history: routed at a local endpoint — unpriced models cost nothing today")
        }
        DayAggregator.days(records, range, calendar, definition.sessionGap, prices, freeOnSeconds = freeDay)
    }

    /** The [count] days ending today. */
    suspend fun days(last: Int): List<DailyUsageStat> = days(DateRange.last(last, now(), calendar))

    /** A definition's `usageHistory` block: the JSON, no behaviour. */
    @Serializable
    data class Definition(
        val records: Records,
        /** What a token costs, when the log doesn't say. */
        val prices: Prices? = null,
        val freeWhen: FreeWhen? = null,
        /** A pause longer than this many seconds starts a working session; without one, each record is a session and no working time is known. */
        val sessionGap: Double? = null,
        /**
         * Other apps on this Mac that use the same plan and keep their own count — each read on
         * its own, never added to these records. An added login's patch sets it to `null`: the
         * apps belong to the Mac.
         */
        val otherApps: List<OtherApp>? = null,
    ) {
        fun toJson(): JsonElement = DefinitionJson.encodeToJsonElement(this)

        /** The definition with [patch] merged in (RFC 7396). */
        fun patched(patch: JsonElement): Definition = from(toJson().merged(patch))

        /** The definition with every `{{<scope>.<name>}}` in its strings replaced by `values[name]`. */
        fun filled(values: Map<String, String>, scope: String): Definition =
            from(toJson().mapStrings { Placeholders.fill(it, values, scope) })

        /** The `{{<scope>.<name>}}` names still in the definition, sorted. */
        fun unfilled(scope: String): List<String> {
            val names = mutableSetOf<String>()
            toJson().mapStrings { names += Placeholders.names(it, scope); it }
            return names.sorted()
        }

        companion object {
            fun from(json: JsonElement): Definition = decoding("usageHistory") { DefinitionJson.decodeFromJsonElement(json) }
        }
    }

    /** Another app's usage, read like a login's own logs and shown under its own name. Without prices it has tokens and no cost. */
    @Serializable
    data class OtherApp(val label: String, val records: Records, val prices: Prices? = null) {
        /** How its days are read: its own records and prices, nothing of the login's. */
        val definition: Definition get() = Definition(records = records, prices = prices)
    }

    /**
     * The log: where its files are and how they're laid out, and the shape a usage record is
     * written in — or its `shapes`, when the log writes one more than one way.
     */
    @Serializable(with = RecordsSerializer::class)
    data class Records(
        /** A glob: `**` any depth, `*` within one name; `~` and `${VAR:-default}` expand. */
        val files: String,
        val format: Format = Format.JSON_LINES,
        /** The ways the log writes a record, in order: a line is read by the first whose `where` holds, and by it alone. */
        val shapes: List<Shape>,
    ) {
        /** A log that writes a record one way, its fields given inline. */
        constructor(
            files: String,
            format: Format = Format.JSON_LINES,
            condition: Match? = null,
            at: At,
            id: List<String> = emptyList(),
            model: String? = null,
            tokens: Tokens = Tokens(),
            cost: String? = null,
        ) : this(files, format, listOf(Shape(condition, at, id, model, tokens, cost)))
    }

    /** One way a log writes a usage record, read whole: its own filter and paths, never another shape's. */
    @OptIn(ExperimentalSerializationApi::class)
    @Serializable
    data class Shape(
        /** Only the records where this holds; its text is also a byte prefilter. */
        @SerialName("where") val condition: Match? = null,
        /** When — a field (ISO 8601 text or epoch seconds), or the file's path. */
        val at: At,
        /** Together, a record's identity: written twice, it counts once — the last wins. */
        @EncodeDefault val id: List<String> = emptyList(),
        val model: String? = null,
        @EncodeDefault val tokens: Tokens = Tokens(),
        /** The log's own cost, which wins over any price. */
        val cost: String? = null,
    )

    /** How a log is laid out — a closed list, one reader per case. */
    @Serializable
    enum class Format {
        /** One JSON object per line, appended to; read incrementally. */
        @SerialName("jsonLines") JSON_LINES,

        /** One JSON document per file, one record. */
        @SerialName("json") JSON,
    }

    /** When a record happened: a field of it, or — for a tool that names its files by time — the file's path. */
    @Serializable(with = AtSerializer::class)
    sealed class At {
        /** A path to ISO 8601 text or epoch seconds. */
        data class Field(val path: String) : At()

        /** The time in a file's path: the first capture of `pattern`, read with `format` in `timeZone` — never local unless it says so. */
        @Serializable
        data class FromPath(
            @SerialName("fromPath") val pattern: String,
            val format: String,
            val timeZone: String? = null,
        ) : At()

        /**
         * A field's text read with `format` in `timeZone` — the user's own zone unless it says
         * otherwise, so `2026-05-28` is that local day.
         */
        @Serializable
        data class Formatted(val field: String, val format: String, val timeZone: String? = null) : At()
    }

    /** Token counts by kind; a missing one counts 0. `total` stands in when a log keeps only the sum. */
    @Serializable
    data class Tokens(
        val input: String? = null,
        val output: String? = null,
        val cacheWrite: String? = null,
        /** The part of `cacheWrite` kept an hour, which costs more than a five-minute write. */
        val cacheWrite1h: String? = null,
        val cacheRead: String? = null,
        val total: String? = null,
        /** The log's input count already holds its cache reads, so they are taken out of it. */
        val inputIncludesCacheRead: Boolean? = null,
    )

    /** A price file shipped beside the definition. */
    @Serializable
    data class Prices(val file: String)

    @Serializable
    data class FreeWhen(val localEndpoint: LocalEndpointRule? = null)

    /** An unpriced model costs nothing when a base URL in `file` is on this Mac. */
    @Serializable
    data class LocalEndpointRule(
        val file: String,
        /** The first entry that answers decides; a list of paths is one entry, and `[*]` walks every element of a list. */
        @Serializable(with = UrlEntriesSerializer::class) val url: List<List<String>>,
    )

    /**
     * `{ "path": "kind", "equals": "reply" }` — a value in the record equals this JSON value.
     * The mapping's `Match`, kept here until the mapping area lands in Kotlin.
     */
    @Serializable
    data class Match(val path: String, @SerialName("equals") val value: JsonElement) {
        /** Whether the value at [path] equals [value]. */
        fun holds(scope: JsonScope): Boolean {
            val found = scope.value(path)
            return when (val expected = value) {
                is JsonNull -> found == null || found is JsonNull
                is JsonPrimitive -> when {
                    expected.isString -> found is JsonPrimitive && found.isString && found.content == expected.content
                    expected.booleanOrNull != null ->
                        found is JsonPrimitive && !found.isString && found.booleanOrNull == expected.booleanOrNull
                    else -> !(found is JsonPrimitive && found.isString) &&
                        JsonPath.number(found) != null && JsonPath.number(found) == JsonPath.number(expected)
                }
                else -> found != null && sameValue(found, expected)
            }
        }

        /** Foundation's equality: numbers by value, `1` equal to `1.0`. */
        private fun sameValue(a: JsonElement, b: JsonElement): Boolean = when {
            a is JsonObject && b is JsonObject -> a.keys == b.keys && a.all { (key, item) -> sameValue(item, b.getValue(key)) }
            a is JsonArray && b is JsonArray -> a.size == b.size && a.indices.all { sameValue(a[it], b[it]) }
            a is JsonNull || b is JsonNull -> a is JsonNull && b is JsonNull
            a is JsonPrimitive && b is JsonPrimitive -> when {
                a.isString || b.isString -> a.isString && b.isString && a.content == b.content
                else -> a.content == b.content || (JsonPath.number(a) != null && JsonPath.number(a) == JsonPath.number(b))
            }
            else -> false
        }
    }

    companion object {
        /**
         * A login's usage log, reading this Mac's files. [scripts] finds the price file shipped
         * beside the definition; [home] and [environment] expand `~` and `${VAR:-default}`.
         */
        fun make(
            definition: Definition,
            home: String,
            environment: (String) -> String?,
            scripts: (String) -> String? = { null },
            calendar: LocalCalendar = localCalendar(),
            now: () -> Double,
        ): UsageLog {
            val expand = { path: String -> Paths.expand(path, home, environment) }
            // Other apps are read on their own, so they never change how these days were summed.
            val own = Definition(definition.records, definition.prices, definition.freeWhen, definition.sessionGap)
            val hash = SHA256()
            hash.update(SwiftJson.encode(own.toJson()).encodeToByteArray())
            hash.update(expand(definition.records.files).encodeToByteArray())
            hash.update((definition.prices?.let { scripts(it.file) } ?: "").encodeToByteArray())
            val fingerprint = hash.digest().joinToString("") { (it.toInt() and 0xff).toString(16).padStart(2, '0') }
            return UsageLog(
                definition = definition,
                reader = LogReader.of(definition.records),
                prices = definition.prices?.let { PriceList.load(it.file, scripts) },
                localEndpoint = definition.freeWhen?.localEndpoint?.let { LocalEndpoint(expand(it.file), it.url) },
                files = expand(definition.records.files),
                calendar = calendar,
                now = now,
                fingerprint = fingerprint,
            )
        }
    }
}
