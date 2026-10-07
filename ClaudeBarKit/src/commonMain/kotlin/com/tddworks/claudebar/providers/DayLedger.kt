package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.logs.LocalCalendar
import com.tddworks.claudebar.datasources.mapping.DecimalMoney
import com.tddworks.claudebar.quotas.DailyUsageStat
import kotlinx.io.buffered
import kotlinx.io.files.Path
import kotlinx.io.files.SystemFileSystem
import kotlinx.io.readString
import kotlinx.io.writeString
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.JsonUnquotedLiteral
import kotlin.math.abs
import kotlin.math.floor

/**
 * PAST DAYS, KEPT — a closed day is summed once and kept on this Mac, so a thirty-day range
 * reads only its open days from the logs. A cache, not a record: deleting it reads the logs
 * again, and a change to how the logs read (the log's fingerprint) starts it over.
 */
internal class DayLedger(
    private val store: LedgerStore,
    /** Whose days these are — the login's lineup id. */
    private val key: String,
) {
    /** The kept days, by date, when they were summed the way [fingerprint] reads. */
    fun days(fingerprint: String): Map<String, DailyUsageStat> {
        val page = store.load(key) ?: return emptyMap()
        return if (page.fingerprint == fingerprint) page.days else emptyMap()
    }

    /** Keeps [days], beside those already kept the same way. */
    fun keep(days: Map<String, DailyUsageStat>, fingerprint: String) {
        if (days.isEmpty()) return
        store.save(LedgerPage(fingerprint, days(fingerprint) + days), key)
    }

    companion object {
        /** A day closes this long after its midnight: lines a tool writes late still land, and the day is final after that. */
        const val CLOSES_AFTER_SECONDS = 3600.0

        /** Whether the day starting at [daySeconds] is closed at [nowSeconds]. */
        fun isClosed(daySeconds: Double, nowSeconds: Double, calendar: LocalCalendar): Boolean {
            val end = calendar.addingDays(1, daySeconds)
            if (end <= daySeconds) return false
            return nowSeconds >= end + CLOSES_AFTER_SECONDS
        }

        /** The day's name, `yyyy-MM-dd`, in this Mac's calendar — the ledger's key for it. */
        fun name(daySeconds: Double): String = localDayName(daySeconds)
    }
}

/** `yyyy-MM-dd` of the local day holding [atSeconds], in this Mac's calendar and time zone. */
internal expect fun localDayName(atSeconds: Double): String

/** One login's kept days, and how they were read. */
internal data class LedgerPage(
    val fingerprint: String,
    /** By local date, `yyyy-MM-dd`. */
    val days: Map<String, DailyUsageStat>,
) {
    /**
     * The file Swift wrote and still reads (`DailyUsageStat.Stored`): `date` in seconds since
     * 2001 (Foundation's reference date), money as JSON numbers, counts as integers.
     */
    fun toJson(): JsonObject = JsonObject(mapOf(
        "fingerprint" to JsonPrimitive(fingerprint),
        "days" to JsonObject(days.mapValues { (_, day) -> stored(day) }),
    ))

    companion object {
        /** Seconds from 1970 to Foundation's reference date, 2001-01-01. */
        private const val REFERENCE_DATE = 978_307_200.0

        fun from(json: JsonElement): LedgerPage {
            val o = json as JsonObject
            val fingerprint = (o["fingerprint"] as JsonPrimitive).also { require(it.isString) }.content
            val days = (o["days"] as JsonObject).mapValues { (_, day) -> stat(day as JsonObject) }
            return LedgerPage(fingerprint, days)
        }

        private fun stored(day: DailyUsageStat): JsonObject = JsonObject(mapOf(
            "date" to number(day.dateSeconds - REFERENCE_DATE),
            "totalCost" to money(day.totalCostNanos),
            "totalTokens" to JsonPrimitive(day.totalTokens),
            "workingTime" to number(day.workingTime),
            "sessionCount" to JsonPrimitive(day.sessionCount),
            "inputTokens" to JsonPrimitive(day.inputTokens),
            "outputTokens" to JsonPrimitive(day.outputTokens),
            "cacheCreationTokens" to JsonPrimitive(day.cacheCreationTokens),
            "cacheReadTokens" to JsonPrimitive(day.cacheReadTokens),
            "cachedSavings" to money(day.cachedSavingsNanos),
        ))

        private fun stat(o: JsonObject): DailyUsageStat {
            fun text(key: String) = (o[key] as JsonPrimitive).also { require(!it.isString) }.content
            fun count(key: String): Long = text(key).let { it.toLongOrNull() ?: it.toDouble().also { d -> require(d == floor(d)) }.toLong() }
            fun seconds(key: String): Double = text(key).toDouble()
            fun nanos(key: String): Long = requireNotNull(DecimalMoney.nanos(text(key)))
            return DailyUsageStat(
                dateSeconds = seconds("date") + REFERENCE_DATE,
                totalCostNanos = nanos("totalCost"),
                totalTokens = count("totalTokens"),
                workingTime = seconds("workingTime"),
                sessionCount = count("sessionCount"),
                inputTokens = count("inputTokens"),
                outputTokens = count("outputTokens"),
                cacheCreationTokens = count("cacheCreationTokens"),
                cacheReadTokens = count("cacheReadTokens"),
                cachedSavingsNanos = nanos("cachedSavings"),
            )
        }

        /** A whole number of seconds without a fraction, as Foundation writes it. */
        private fun number(value: Double): JsonPrimitive =
            if (value.isFinite() && value == floor(value) && abs(value) < 1e15) JsonPrimitive(value.toLong()) else JsonPrimitive(value)

        /** Nano-units as the exact decimal a `Decimal` is written as — `0.0105`, never a binary float. */
        @OptIn(ExperimentalSerializationApi::class)
        private fun money(nanos: Long): JsonPrimitive {
            val negative = nanos < 0
            val magnitude = nanos.toBigMagnitude()
            val whole = magnitude / 1_000_000_000uL
            val fraction = (magnitude % 1_000_000_000uL).toString().padStart(9, '0').trimEnd('0')
            val text = (if (negative) "-" else "") + whole + (if (fraction.isEmpty()) "" else ".$fraction")
            return JsonUnquotedLiteral(text)
        }

        private fun Long.toBigMagnitude(): ULong = if (this == Long.MIN_VALUE) Long.MAX_VALUE.toULong() + 1uL else abs(this).toULong()
    }
}

/** Where kept days live. */
internal interface LedgerStore {
    fun load(key: String): LedgerPage?

    fun save(page: LedgerPage, key: String)
}

/** `~/.claudebar/usage-history/<login>.json` — a few hundred bytes a day. */
internal class FileLedgerStore(val directory: String) : LedgerStore {
    override fun load(key: String): LedgerPage? = runCatching {
        val text = SystemFileSystem.source(file(key)).buffered().use { it.readString() }
        LedgerPage.from(Json.parseToJsonElement(text))
    }.getOrNull()

    override fun save(page: LedgerPage, key: String) {
        runCatching {
            SystemFileSystem.createDirectories(Path(directory))
            val file = file(key)
            val writing = Path("$file.writing")
            SystemFileSystem.sink(writing).buffered().use { it.writeString(page.toJson().toString()) }
            SystemFileSystem.atomicMove(writing, file)
        }
    }

    private fun file(key: String): Path {
        val safe = key.map { if (it.isLetter() || it.isNumber() || it == '.' || it == '-' || it == '_') it else '_' }.joinToString("")
        return Path(directory, "$safe.json")
    }

    private fun Char.isNumber(): Boolean =
        category == CharCategory.DECIMAL_DIGIT_NUMBER || category == CharCategory.LETTER_NUMBER || category == CharCategory.OTHER_NUMBER

    companion object {
        fun defaultDirectory(home: String): String = Path(home, ".claudebar", "usage-history").toString()
    }
}
