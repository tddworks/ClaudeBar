package com.tddworks.claudebar.datasources.mapping

import com.tddworks.claudebar.datasources.JsonPath
import com.tddworks.claudebar.datasources.JsonScope
import com.tddworks.claudebar.datasources.MappingFacts
import com.tddworks.claudebar.datasources.Reading
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.diagnostics.AppLog
import com.tddworks.claudebar.quotas.AccountTier
import com.tddworks.claudebar.quotas.CostUsage
import com.tddworks.claudebar.quotas.Left
import com.tddworks.claudebar.quotas.Money
import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageError
import com.tddworks.claudebar.quotas.UsageQuota
import com.tddworks.claudebar.quotas.UsageSnapshot
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.time.ExperimentalTime
import kotlin.time.Instant

/** `json` — reads a JSON response by paths into today's `UsageSnapshot`. */
internal class JSONMapper(val mapping: JSONMapping, private val now: () -> Double) : Reading {
    override fun read(response: Response, facts: MappingFacts, providerId: String): UsageSnapshot {
        val document = runCatching { Json.parseToJsonElement(response.text) }.getOrNull()
            ?.takeIf { it is JsonObject || it is JsonArray }
            ?: throw UsageError.ParseFailed("Response is not JSON")
        mapping.notAnObject?.let { reason -> if (document !is JsonObject) throw UsageError.ParseFailed(reason) }
        val scope = JsonScope(document, response.headers, facts.credential, facts.context)

        var quotas = mutableListOf<UsageQuota>()
        for (rule in mapping.quotas) {
            var made = quotas(rule, scope, providerId)
            if (rule.unique) {
                val seen = quotas.map { it.quotaType }.toMutableSet()
                made = made.filter { seen.add(it.quotaType) }
            }
            quotas += made
        }
        val empty = mapping.whenEmpty
        if (quotas.isEmpty() && empty != null) {
            val condition = empty.condition
            if (condition != null && scope.string(condition.path) == condition.equals) {
                quotas = empty.quotas.flatMap { quotas(it, scope, providerId) }.toMutableList()
            } else if (empty.otherwise != null) {
                throw UsageError.ParseFailed(empty.otherwise)
            }
        }

        // Nothing answering is not a failure unless `whenEmpty` says so: a provider with no usage yet reports none.
        val cost = mapping.cost.firstNotNullOfOrNull { cost(it, scope, providerId) }

        return UsageSnapshot(
            providerId = providerId,
            quotas = quotas,
            capturedAtSeconds = now(),
            accountEmail = mapping.email.firstNotNullOfOrNull { scope.string(it)?.takeIf(String::isNotEmpty) },
            accountOrganization = null,
            loginMethod = null,
            accountTier = mapping.plan?.let { plan(it, scope) },
            costUsage = cost,
            dailyUsageReport = null,
            extensionMetrics = null,
        )
    }

    // Quotas

    private fun quotas(rule: QuotaRule, scope: JsonScope, providerId: String): List<UsageQuota> {
        val base = rule.at?.let { scope.moved(scope.value(it)) } ?: scope
        val each = rule.each ?: return listOfNotNull(quota(rule, rule.name?.text, base, providerId))

        var elements = when (val value = base.value(each)) {
            is JsonArray -> value.map { base.moved(it) }
            is JsonObject -> value.keys.sorted().filter { it !in rule.skipKeys }.map { base.moved(value[it], key = it) }
            else -> return emptyList()
        }
        rule.condition?.let { condition -> elements = elements.filter { holds(condition, it) } }

        return elements.flatMap { element ->
            val name = name(rule.name, element)?.takeIf { it.isNotEmpty() } ?: return@flatMap emptyList()
            rule.windows.ifEmpty { listOf(QuotaRule.WindowPick("")) }.mapNotNull { pick ->
                val window = if (pick.at.isEmpty()) element else element.moved(element.value(pick.at))
                quota(rule, name + pick.suffix, window, providerId)
            }
        }
    }

    private fun quota(rule: QuotaRule, name: String?, scope: JsonScope, providerId: String): UsageQuota? {
        rule.left?.let { return moneyQuota(it, rule, name, scope, providerId) }
        val used = first(rule.usedPercent, scope)
        val left = when {
            used != null -> if (rule.overLimit) 100 - used else max(0.0, 100 - used)
            else -> first(rule.leftPercent, scope) ?: return null
        }
        val resetsAt = rule.resetsAt.firstNotNullOfOrNull { date(it, scope) }
        val windowSeconds = windowLength(rule, scope)
        val type = quotaType(rule.kind, name) ?: return null
        return UsageQuota(
            percentRemaining = left,
            quotaType = type,
            providerId = providerId,
            resetsAtSeconds = resetsAt,
            resetText = rule.resetText ?: resetsAt?.let { countdown(rule.countdown, it) },
            windowSeconds = windowSeconds,
            dollarRemainingNanos = null,
            dollarUsedNanos = null,
            dollarCapNanos = null,
            group = null,
            compactTitle = null,
            menuBarTitle = null,
            currency = null,
        )
    }

    private fun countdown(style: QuotaRule.Countdown, untilSeconds: Double): String? = when (style) {
        QuotaRule.Countdown.DAYS -> ResetCountdown.text(untilSeconds, now())
        QuotaRule.Countdown.HOURS -> ResetCountdown.hoursText(untilSeconds, now())
    }

    /** Money left — of a ceiling, or a balance with no percentage at all. */
    private fun moneyQuota(rule: QuotaRule.MoneyLeft, quotaRule: QuotaRule, name: String?, scope: JsonScope, providerId: String): UsageQuota? {
        val type = quotaType(quotaRule.kind, name) ?: return null
        val remaining = money(rule.money, scope) ?: return null
        val currency = rule.currency ?: "USD"
        var ceiling: Money? = null
        val of = rule.of
        if (of != null && isPresent(of, scope)) {
            ceiling = Money(money(of, scope) ?: return null, currency)
        }
        val resetsAt = quotaRule.resetsAt.firstNotNullOfOrNull { date(it, scope) }
        return UsageQuota(
            left = Left.Balance(Money(remaining, currency), ceiling),
            quotaType = type,
            providerId = providerId,
            resetsAtSeconds = resetsAt,
            resetText = quotaRule.resetText ?: resetsAt?.let { countdown(quotaRule.countdown, it) },
            windowSeconds = windowLength(quotaRule, scope),
            group = null,
            compactTitle = null,
            menuBarTitle = null,
        )
    }

    private fun windowLength(rule: QuotaRule, scope: JsonScope): Double? = rule.window.firstNotNullOfOrNull { ref ->
        when (ref) {
            is DurationRef.Seconds -> scope.number(ref.path)
            is DurationRef.Minutes -> scope.number(ref.path)?.let { it * 60 }
            is DurationRef.Fixed -> ref.seconds
        }
    }

    private fun name(rule: NameRule?, scope: JsonScope): String? {
        if (rule == null) return null
        rule.text?.let { return it }
        val raw = rule.firstOf.firstNotNullOfOrNull { path -> scope.string(path)?.takeIf { it.isNotEmpty() } } ?: return null
        var name = raw.trim { it == '\t' || it.category == CharCategory.SPACE_SEPARATOR }
        if (rule.firstWord) name = name.split(' ').firstOrNull { it.isNotEmpty() } ?: ""
        if (rule.lowercase) name = name.lowercase()
        for (drop in rule.dropPrefixes) {
            if (!name.lowercase().startsWith(drop.prefix.lowercase())) continue
            val rest = name.drop(drop.prefix.length)
            if (rest.isEmpty()) return name
            return if (drop.capitalize) rest.take(1).uppercase() + rest.drop(1) else rest
        }
        return name
    }

    // Values

    private fun first(refs: List<ValueRef>, scope: JsonScope): Double? {
        for (ref in refs) {
            when (ref) {
                is ValueRef.Constant -> return ref.value
                is ValueRef.Path -> scope.number(ref.path)?.let { return it }
            }
        }
        return null
    }

    private fun date(ref: ResetRef, scope: JsonScope): Double? = when (ref) {
        is ResetRef.EpochSeconds -> scope.number(ref.path)
        is ResetRef.SecondsFromNow -> scope.number(ref.path)?.let { now() + it }
        is ResetRef.Iso8601 -> scope.string(ref.path)?.let(::iso8601Seconds)
    }

    private fun plan(rule: PlanRule, scope: JsonScope): AccountTier? {
        val value = scope.string(rule.path)?.takeIf { it.isNotEmpty() } ?: return null
        if (rule.plans.isNotEmpty()) return ScriptOutput.tier(rule.plans[value.lowercase()] ?: value)
        return AccountTier.Custom(rule.badges[value.lowercase()] ?: value.uppercase())
    }

    private fun cost(rule: CostRule, scope: JsonScope, providerId: String): CostUsage? {
        rule.condition?.let { if (!holds(it, scope)) return null }
        // A limit that is there but is not money drops the rule: an invalid cap must not read as "no cap".
        var limit: Long? = null
        val limitAmount = rule.limit
        if (limitAmount != null && isPresent(limitAmount, scope)) limit = money(limitAmount, scope) ?: return null
        val used: Long = when {
            rule.used != null -> money(rule.used, scope) ?: return null
            else -> {
                val remaining = first(rule.remaining, scope)?.let(DecimalMoney::nanos)
                if (remaining == null || limit == null) return null
                max(0L, min(limit, limit - remaining))
            }
        }
        return CostUsage(
            totalCostNanos = used,
            budgetNanos = limit,
            apiDuration = 0.0,
            wallDuration = 0.0,
            linesAdded = 0,
            linesRemoved = 0,
            providerId = providerId,
            kind = if (rule.kind == CostRule.Kind.EXTRA_USAGE) CostUsage.Kind.EXTRA_USAGE else CostUsage.Kind.API_COST,
            capturedAtSeconds = now(),
            resetsAtSeconds = null,
            resetText = null,
            lines = emptyList(),
        )
    }

    private fun isPresent(amount: Amount, scope: JsonScope): Boolean = when (amount) {
        is Amount.Value -> amount.refs.any { it !is ValueRef.Path || scope.value(it.path) != null }
        is Amount.MinorUnits -> scope.value(amount.amount) != null
    }

    /** Nano-units, read from a number's own text so 12.4 stays 12.4. */
    private fun money(amount: Amount, scope: JsonScope): Long? = when (amount) {
        is Amount.Value -> run {
            for (ref in amount.refs) {
                when (ref) {
                    is ValueRef.Constant -> return@run DecimalMoney.nanos(ref.value)
                    is ValueRef.Path -> {
                        val value = scope.value(ref.path) as? JsonPrimitive ?: continue
                        if (value.isNumber) return@run DecimalMoney.nanos(value.content)
                        // An amount sent as text stays exact — decimal text only, never hex.
                        val text = value.takeIf { it.isString }?.content?.trim()
                        if (text != null && DecimalMoney.isDecimal(text)) return@run DecimalMoney.nanos(text)
                    }
                }
            }
            null
        }
        is Amount.MinorUnits -> run {
            val minor = (scope.value(amount.amount) as? JsonPrimitive)?.takeIf { it.isNumber }?.content ?: return@run null
            if (minor.startsWith('-') && DecimalMoney.nanos(minor).let { it == null || it < 0 }) return@run null
            val places = first(amount.decimals, scope) ?: return@run null
            if (places < 0 || floor(places) != places || places > 38) return@run null
            DecimalMoney.nanos(shifted(minor, places.toInt()))
        }
    }

    /** `minor` with its point moved [places] to the left, as decimal text. */
    private fun shifted(minor: String, places: Int): String {
        val mantissa = minor.substringBefore('e').substringBefore('E')
        val exponent = minor.substring(mantissa.length).drop(1).ifEmpty { "0" }.toInt()
        return "${mantissa}e${exponent - places}"
    }

    companion object {
        fun quotaType(kind: QuotaKind, name: String?): QuotaType? = when (kind) {
            QuotaKind.SESSION -> QuotaType.Session
            QuotaKind.WEEKLY -> QuotaType.Weekly
            QuotaKind.MODEL -> name?.let(QuotaType::ModelSpecific)
            QuotaKind.TIME -> name?.let(QuotaType::TimeLimit)
        }

        /** Whether the value at the condition's path equals its JSON value — a number equals a number however written. */
        fun holds(condition: Match, scope: JsonScope): Boolean {
            val value = scope.value(condition.path)
            return when (val expected = condition.equals) {
                JsonNull -> value == null || value is JsonNull
                is JsonPrimitive -> when {
                    expected.isString -> value is JsonPrimitive && value.isString && value.content == expected.content
                    expected.booleanOrNull != null -> value is JsonPrimitive && value.isBoolean && value.booleanOrNull == expected.booleanOrNull
                    else -> value is JsonPrimitive && !value.isString && JsonPath.number(value) == JsonPath.number(expected)
                }
                else -> value != null && sameJson(value, expected)
            }
        }

        /** Foundation's `isEqual` over JSON: numbers (and yes/no, as 1/0) by value. */
        private fun sameJson(a: JsonElement, b: JsonElement): Boolean = when {
            a is JsonObject && b is JsonObject -> a.keys == b.keys && a.all { (key, value) -> sameJson(value, b.getValue(key)) }
            a is JsonArray && b is JsonArray -> a.size == b.size && a.indices.all { sameJson(a[it], b[it]) }
            a is JsonNull || b is JsonNull -> a is JsonNull && b is JsonNull
            a is JsonPrimitive && b is JsonPrimitive -> when {
                a.isString || b.isString -> a.isString && b.isString && a.content == b.content
                else -> numeric(a) == numeric(b)
            }
            else -> false
        }

        private fun numeric(value: JsonPrimitive): Double? =
            value.booleanOrNull?.let { if (it) 1.0 else 0.0 } ?: value.content.toDoubleOrNull()
    }
}

private val JsonPrimitive.isBoolean: Boolean get() = !isString && this !is JsonNull && booleanOrNull != null
private val JsonPrimitive.isNumber: Boolean get() = !isString && this !is JsonNull && booleanOrNull == null

/** RFC 3339 text — `2026-03-17T23:00:00Z`, fractional seconds allowed unless [fractional] is false — in Unix seconds. */
@OptIn(ExperimentalTime::class)
internal fun iso8601Seconds(text: String, fractional: Boolean = true): Double? {
    if (!fractional && Regex("""T\d{2}:\d{2}:\d{2}\.""").containsMatchIn(text)) return null
    val instant = runCatching { Instant.parse(text) }.getOrNull() ?: return null
    return instant.epochSeconds + instant.nanosecondsOfSecond / 1e9
}

/** `text` — reads a terminal screen: a known error phrase fails the read; otherwise each quota's label and the percentage within a few lines of it. */
internal class TextMapper(val mapping: TextMapping, private val now: () -> Double) : Reading {
    override fun read(response: Response, facts: MappingFacts, providerId: String): UsageSnapshot {
        val screen = stripANSI(response.text)
        val lower = screen.lowercase()

        for (rule in mapping.errors) {
            val any = rule.contains.any { lower.contains(it.lowercase()) }
            val all = rule.alsoContains.all { lower.contains(it.lowercase()) }
            if (any && all) {
                AppLog.probes.error("$providerId screen reports: ${rule.contains.firstOrNull() ?: "an error"}")
                throw rule.error.usageError
            }
        }

        val lines = screen.split(newlines)
        val quotas = mapping.quotas.mapNotNull { pattern ->
            val type = JSONMapper.quotaType(pattern.kind, pattern.name) ?: return@mapNotNull null
            val left = pattern.leftPercent?.let { percent(pattern.label, it, pattern.lookahead, lines) }
                ?: pattern.usedPercent?.let { regex -> percent(pattern.label, regex, pattern.lookahead, lines)?.let { max(0.0, 100 - it) } }
                ?: return@mapNotNull null
            UsageQuota(left, type, providerId, null, null, null, null, null, null, null, null, null, null)
        }

        if (quotas.isEmpty()) throw UsageError.ParseFailed(mapping.whenEmpty ?: "Could not find usage limits")
        return UsageSnapshot(providerId, quotas, now(), null, null, null, null, null, null, null)
    }

    companion object {
        /** Foundation's `.newlines`: each of LF, VT, FF, CR, NEL, LS and PS ends a line. */
        private val newlines = Regex("[\n\u000B\u000C\r\u0085  ]")
        private val ansi = Regex("""\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])""")

        fun stripANSI(text: String): String = ansi.replace(text, "")

        fun percent(label: String, pattern: String, lookahead: Int, lines: List<String>): Double? {
            val regex = runCatching { Regex(pattern, RegexOption.IGNORE_CASE) }.getOrNull() ?: return null
            val lowerLabel = label.lowercase()
            for ((index, line) in lines.withIndex()) {
                if (!line.lowercase().contains(lowerLabel)) continue
                for (candidate in lines.subList(index, min(lines.size, index + lookahead).coerceAtLeast(index))) {
                    val match = regex.find(candidate) ?: continue
                    val group = match.groupValues.getOrNull(1)?.takeIf { match.groups[1] != null } ?: continue
                    plainNumber(group)?.let { return it }
                }
            }
            return null
        }

        /** Swift's `Double(text)`: a plain decimal, no padding or suffix. */
        private fun plainNumber(text: String): Double? =
            text.takeIf { Regex("""[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?""").matches(it) }?.toDoubleOrNull()
    }
}

/** "Resets in 2d 5h 30m" — the countdown a CLI's screen shows as `resetText`. */
internal object ResetCountdown {
    fun text(untilSeconds: Double, nowSeconds: Double): String {
        val interval = untilSeconds - nowSeconds
        if (interval <= 0) return "Resets soon"
        val days = (interval / 86400).toInt()
        val hours = (interval % 86400 / 3600).toInt()
        val minutes = (interval % 3600 / 60).toInt()
        return when {
            days > 0 -> "Resets in ${days}d ${hours}h ${minutes}m"
            hours > 0 -> "Resets in ${hours}h ${minutes}m"
            minutes > 0 -> "Resets in ${minutes}m"
            else -> "Resets soon"
        }
    }

    /** The same in hours, never days — "Resets in 53h 30m". null once past. */
    fun hoursText(untilSeconds: Double, nowSeconds: Double): String? {
        val interval = untilSeconds - nowSeconds
        if (interval <= 0) return null
        val hours = (interval / 3600).toInt()
        val minutes = (interval % 3600 / 60).toInt()
        return when {
            hours > 0 -> "Resets in ${hours}h ${minutes}m"
            minutes > 0 -> "Resets in ${minutes}m"
            else -> "Resets soon"
        }
    }
}
