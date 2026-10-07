package com.tddworks.claudebar.datasources.logs

import com.tddworks.claudebar.datasources.JsonScope
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

/** One usage record, whatever log it came from — the shape every reader yields, so nothing after the reader knows which tool wrote it. */
internal class LogRecord(
    val atSeconds: Double,
    /** The record's identity, when every `id` path answered; null is never merged with another record. */
    val id: String? = null,
    val model: String? = null,
    val input: Long = 0,
    val output: Long = 0,
    val cacheWrite: Long = 0,
    cacheWrite1h: Long = 0,
    val cacheRead: Long = 0,
    /** The log's own sum, when it keeps only that. */
    val total: Long? = null,
    /** The log's own cost, which wins over any price. */
    val cost: NanoAmount? = null,
) {
    /** The part of [cacheWrite] kept an hour. */
    val cacheWrite1h: Long = min(cacheWrite1h, cacheWrite)

    /** Input and output — what *TODAY'S USAGE* counts as tokens. */
    val tokens: Long get() = total ?: (input + output)

    private val fields get() = listOf(atSeconds, id, model, input, output, cacheWrite, cacheWrite1h, cacheRead, total, cost)

    override fun equals(other: Any?) = other is LogRecord && other.fields == fields
    override fun hashCode() = fields.hashCode()
    override fun toString() = "LogRecord(at=$atSeconds, id=$id, model=$model, input=$input, output=$output, " +
        "cacheWrite=$cacheWrite, cacheWrite1h=$cacheWrite1h, cacheRead=$cacheRead, total=$total, cost=$cost)"

    companion object {
        /**
         * Records written twice count once: the **last** copy of an identity wins (a streamed
         * message is logged as it grows), kept where it was first seen. A record with no
         * identity is always kept.
         */
        fun deduplicated(records: List<LogRecord>): List<LogRecord> {
            val last = mutableMapOf<String, LogRecord>()
            val order = mutableListOf<Any>()
            for (record in records) {
                val id = record.id
                if (id != null) {
                    if (id !in last) order += Keyed(id)
                    last[id] = record
                } else {
                    order += record
                }
            }
            return order.map { if (it is Keyed) last.getValue(it.id) else it as LogRecord }
        }

        private class Keyed(val id: String)
    }
}

/** How one shape of a log's records reads: its filter, its paths, and the bytes a line must hold for its `where` to have a chance. */
internal class RecordShape(val shape: UsageLog.Shape) {
    /**
     * The `where` text, quoted as JSON writes it, or null when the shape has no text to look
     * for. Inside a JSON string the quotes would be escaped, so a quoted mention never matches.
     */
    val fragment: ByteArray?
        get() = (shape.condition?.value as? JsonPrimitive)?.takeIf { it.isString }?.let { "\"${it.content}\"".encodeToByteArray() }

    /** Whether this shape's `where` holds for the record in [scope]. */
    fun picks(scope: JsonScope): Boolean = shape.condition?.holds(scope) ?: true

    /** The record in [scope] read whole from this shape's paths, from the file at [path], or null when it has no time or declared model, or says nothing about usage. */
    fun record(scope: JsonScope, path: String): LogRecord? {
        val at = time(scope, path) ?: return null
        var model: String? = null
        if (shape.model != null) model = scope.string(shape.model) ?: return null
        val tokens = shape.tokens
        val read = listOf(tokens.input, tokens.output, tokens.cacheWrite, tokens.cacheRead, tokens.total, tokens.cacheWrite1h)
            .map { path -> path?.let { scope.number(it) } }
        // A count is a whole number of tokens: a negative or a fraction is a log that changed shape, not usage.
        if (!read.all { it == null || (it >= 0 && floor(it) == it) }) return null
        val counts = read.map { it?.toLong() }
        val cost = shape.cost?.let { amount(scope.value(it)) }
        // A record that says nothing about usage isn't usage.
        if (counts.take(5).all { it == null } && cost == null) return null
        val parts = shape.id.map { scope.string(it) }
        val id = if (parts.isEmpty() || parts.any { it == null }) null else parts.joinToString("\u001F")
        var input = counts[0] ?: 0
        if (tokens.inputIncludesCacheRead == true) input = max(0, input - (counts[3] ?: 0))
        return LogRecord(
            atSeconds = at, id = id, model = model, input = input, output = counts[1] ?: 0, cacheWrite = counts[2] ?: 0,
            cacheWrite1h = counts[5] ?: 0, cacheRead = counts[3] ?: 0, total = counts[4], cost = cost,
        )
    }

    private fun time(scope: JsonScope, path: String): Double? = when (val at = shape.at) {
        is UsageLog.At.Field -> seconds(scope.value(at.path))
        is UsageLog.At.FromPath -> seconds(path, at)
        is UsageLog.At.Formatted -> scope.string(at.field)?.let { formattedSeconds(it, at.format, at.timeZone) }
    }

    companion object {
        /** The first capture of the rule's pattern in [path], read with its format. */
        fun seconds(path: String, rule: UsageLog.At.FromPath): Double? {
            val regex = runCatching { Regex(rule.pattern) }.getOrNull() ?: return null
            val capture = regex.find(path)?.groups?.get(1)?.value ?: return null
            return formattedSeconds(capture, rule.format, rule.timeZone)
        }

        /** ISO 8601 text, or epoch seconds. */
        fun seconds(value: JsonElement?): Double? {
            val primitive = value as? JsonPrimitive ?: return null
            if (primitive.isString) return LogTimestamps.seconds(primitive.content)
            if (primitive.booleanOrNull != null) return null
            return primitive.content.toDoubleOrNull()
        }

        /** An amount as written — text or number — read exactly. */
        fun amount(value: JsonElement?): NanoAmount? {
            val primitive = value as? JsonPrimitive ?: return null
            if (!primitive.isString && (primitive.booleanOrNull != null || primitive.content == "null")) return null
            return NanoAmount.parse(primitive.content)
        }
    }
}

/** The shapes' `where` texts: a line must hold one before it is decoded; null when a shape has none, which reads every line. */
internal val List<RecordShape>.fragments: List<ByteArray>?
    get() = map { it.fragment ?: return null }

/** The record in [json], read from the file at [path], by the first shape whose `where` holds; null when none does or it can't read it. */
internal fun List<RecordShape>.record(json: JsonElement, path: String = ""): LogRecord? {
    val scope = JsonScope(json)
    return firstOrNull { it.picks(scope) }?.record(scope, path)
}

/** A JSON document — an object or a list, as JSONSerialization reads — or null when the bytes aren't one. */
internal fun jsonDocument(bytes: ByteArray): JsonElement? = runCatching {
    Json.parseToJsonElement(bytes.decodeToString(throwOnInvalidSequence = true))
}.getOrNull()?.takeIf { it is JsonObject || it is JsonArray }

/**
 * An ISO 8601 instant — `2026-07-26T21:03:09.138930Z` — with or without a fraction of a second,
 * read to the millisecond as Swift's `ISO8601DateFormatter` does.
 */
internal object LogTimestamps {
    private val instant = Regex("""^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?(Z|[+-]\d{2}:?\d{2})$""")

    fun seconds(text: String): Double? {
        val match = instant.matchEntire(text) ?: return null
        val (y, mo, d, h, mi, s, fraction, zone) = match.destructured
        val year = y.toInt()
        val month = mo.toInt()
        val day = d.toInt()
        val hour = h.toInt()
        val minute = mi.toInt()
        val second = s.toInt()
        if (month !in 1..12 || day !in 1..daysIn(month, year) || hour > 23 || minute > 59 || second > 59) return null
        val offset = if (zone == "Z") 0 else {
            val digits = zone.substring(1).replace(":", "")
            val hours = digits.substring(0, 2).toInt()
            val minutes = digits.substring(2).toInt()
            if (hours > 23 || minutes > 59) return null
            (hours * 3600 + minutes * 60) * (if (zone[0] == '-') -1 else 1)
        }
        val millis = fraction.take(3).padEnd(3, '0').ifEmpty { "000" }.toInt()
        val whole = daysFromCivil(year, month, day) * 86_400L + hour * 3600 + minute * 60 + second - offset
        return whole + millis / 1000.0
    }

    private fun daysIn(month: Int, year: Int): Int = when (month) {
        2 -> if ((year % 4 == 0 && year % 100 != 0) || year % 400 == 0) 29 else 28
        4, 6, 9, 11 -> 30
        else -> 31
    }

    /** Days since 1970-01-01 of a proleptic Gregorian date (Howard Hinnant's algorithm). */
    private fun daysFromCivil(year: Int, month: Int, day: Int): Long {
        val y = (if (month <= 2) year - 1 else year).toLong()
        val era = (if (y >= 0) y else y - 399) / 400
        val yoe = y - era * 400
        val doy = (153 * (if (month > 2) month - 3 else month + 9) + 2) / 5 + day - 1
        val doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }
}
