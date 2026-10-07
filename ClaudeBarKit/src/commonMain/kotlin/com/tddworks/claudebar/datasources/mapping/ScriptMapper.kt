package com.tddworks.claudebar.datasources.mapping

import com.tddworks.claudebar.datasources.MappingFacts
import com.tddworks.claudebar.datasources.Reading
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.diagnostics.AppLog
import com.tddworks.claudebar.quotas.AccountTier
import com.tddworks.claudebar.quotas.CostLine
import com.tddworks.claudebar.quotas.CostUsage
import com.tddworks.claudebar.quotas.ExtensionMetric
import com.tddworks.claudebar.quotas.Left
import com.tddworks.claudebar.quotas.Money
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

/**
 * A JavaScript engine with no file, network or process access — the script turns text into
 * numbers and nothing else. JavaScriptCore on the Mac.
 */
internal interface ScriptEngine {
    /**
     * Loads [sources] in order into a fresh context holding [strings] as globals and [functions]
     * as global functions of one text argument, then evaluates [expression].
     */
    fun run(
        sources: List<String>,
        strings: Map<String, String>,
        functions: Map<String, (String) -> Double?>,
        expression: String,
    ): ScriptRun
}

/** How a script run ended. */
internal sealed class ScriptRun {
    /** The expression's value as text; null when it was `undefined`. */
    data class Value(val text: String?) : ScriptRun()

    /** The sources threw while loading. */
    data class LoadFailed(val exception: String) : ScriptRun()

    /** The expression threw. */
    data class Threw(val exception: String) : ScriptRun()

    /** No engine could be started. */
    data object Unavailable : ScriptRun()
}

/**
 * `script` — reads a response with a JavaScript file. The script defines `read(response, context)`:
 *
 * - `response` — `{ status, headers, text, json }` (`json` is the parsed body, or `null`)
 * - `context` — `{ now, timeZone, credential, values, ...files }`: Unix seconds, this machine's
 *   zone, the credential values the definition lets it see, the settings it hands over, and each
 *   declared context file's fields
 *
 * and returns `{ quotas, notes, plan, cost, account }` or `{ error }`. It may call
 * `humanDate(text)`, and the [DecimalScript] helpers so money never passes through a binary float.
 */
internal class ScriptMapper(
    val file: String,
    private val source: String?,
    private val values: Map<String, String> = emptyMap(),
    private val engine: ScriptEngine,
    private val now: () -> Double,
    private val zones: TimeZones = systemTimeZones(),
) : Reading {
    override fun read(response: Response, facts: MappingFacts, providerId: String): UsageSnapshot {
        val source = source ?: throw UsageError.ParseFailed("Mapping script '$file' is missing")
        val run = engine.run(
            sources = listOf(DecimalScript.source, source),
            strings = mapOf("__input" to input(response, facts).toString()),
            functions = mapOf("humanDate" to { text -> HumanDate.parse(text, now(), zones) }),
            expression = "JSON.stringify(read(JSON.parse(__input).response, JSON.parse(__input).context))",
        )
        val text = when (run) {
            ScriptRun.Unavailable -> throw UsageError.ExecutionFailed("JavaScriptCore is unavailable")
            is ScriptRun.LoadFailed -> throw UsageError.ParseFailed("Mapping script '$file' failed to load: ${run.exception}")
            is ScriptRun.Threw -> {
                AppLog.probes.error("$providerId mapping script '$file' threw: ${run.exception}")
                throw UsageError.ParseFailed(run.exception)
            }
            is ScriptRun.Value -> run.text?.takeIf { it != "undefined" }
                ?: throw UsageError.ParseFailed("Mapping script '$file' returned nothing")
        }
        val output = try {
            ScriptOutput.from(Json.parseToJsonElement(text))
        } catch (error: Exception) {
            throw UsageError.ParseFailed("Mapping script '$file' returned an unexpected shape: ${error.message}")
        }
        return output.snapshot(providerId, now())
    }

    private fun input(response: Response, facts: MappingFacts): JsonObject {
        val context = mutableMapOf<String, JsonElement>(
            "now" to JsonPrimitive(now()),
            "timeZone" to JsonPrimitive(zones.current),
            "credential" to strings(facts.credential),
            // A blank setting never filled its template.
            "values" to strings(values.filterValues { "{{" !in it }),
        )
        for ((name, fields) in facts.context) context[name] = strings(fields)
        return JsonObject(
            mapOf(
                "response" to JsonObject(
                    mapOf(
                        "status" to (response.status?.let(::JsonPrimitive) ?: JsonNull),
                        "headers" to strings(response.headers),
                        "text" to JsonPrimitive(response.text),
                        "json" to (runCatching { Json.parseToJsonElement(response.text) }.getOrNull() ?: JsonNull),
                    ),
                ),
                "context" to JsonObject(context),
            ),
        )
    }

    private fun strings(values: Map<String, String>) = JsonObject(values.mapValues { JsonPrimitive(it.value) })
}

/** What a mapping script returns, read as strictly as Swift's `JSONDecoder`: a field of the wrong shape fails the read. */
internal class ScriptOutput(
    val quotas: List<Quota>?,
    val notes: List<Note>?,
    val plan: String?,
    val cost: Cost?,
    val account: Account?,
    val error: ErrorRef?,
) {
    class Quota(
        val type: QuotaKind,
        val name: String?,
        /** Exactly one measure: the old percentage or money, optionally of a ceiling. */
        val left: Left,
        val resetsAt: Double?,
        val resetText: String?,
        val windowSeconds: Double?,
        /** The account or source it belongs to, when a report holds several. */
        val group: String?,
    )

    class Cost(
        val kind: CostRule.Kind?,
        val usedNanos: Long,
        val limitNanos: Long?,
        val apiDurationSeconds: Double?,
        val resetsAt: Double?,
        val resetText: String?,
        val lines: List<CostLine>?,
    )

    class Account(val email: String?, val organization: String?, val loginMethod: String?)

    /** A line under a group with nothing to measure — "No usage reported". */
    class Note(val group: String, val text: String, val label: String?)

    fun snapshot(providerId: String, capturedAtSeconds: Double): UsageSnapshot {
        error?.let { throw it.usageError }
        val quotas = quotas.orEmpty().mapNotNull { quota ->
            val type = JSONMapper.quotaType(quota.type, quota.name) ?: return@mapNotNull null
            UsageQuota(quota.left, type, providerId, quota.resetsAt, quota.resetText, quota.windowSeconds, quota.group, null, null)
        }
        val costUsage = cost?.let { cost ->
            CostUsage(
                totalCostNanos = cost.usedNanos,
                budgetNanos = cost.limitNanos,
                apiDuration = cost.apiDurationSeconds ?: 0.0,
                wallDuration = 0.0,
                linesAdded = 0,
                linesRemoved = 0,
                providerId = providerId,
                kind = if (cost.kind == CostRule.Kind.EXTRA_USAGE) CostUsage.Kind.EXTRA_USAGE else CostUsage.Kind.API_COST,
                capturedAtSeconds = capturedAtSeconds,
                resetsAtSeconds = cost.resetsAt,
                resetText = cost.resetText,
                lines = cost.lines.orEmpty(),
            )
        }
        return UsageSnapshot(
            providerId = providerId,
            quotas = quotas,
            capturedAtSeconds = capturedAtSeconds,
            accountEmail = account?.email,
            accountOrganization = account?.organization,
            loginMethod = account?.loginMethod,
            accountTier = plan?.let(::tier),
            costUsage = costUsage,
            dailyUsageReport = null,
            extensionMetrics = notes?.takeIf { it.isNotEmpty() }?.map {
                ExtensionMetric(it.label ?: it.group, it.text, "", null, null, null, null, it.group)
            },
        )
    }

    companion object {
        /** The well-known tiers by name; anything else is a badge as written. */
        fun tier(plan: String): AccountTier = when (plan) {
            "claudeMax" -> AccountTier.ClaudeMax
            "claudePro" -> AccountTier.ClaudePro
            "claudeApi" -> AccountTier.ClaudeApi
            else -> AccountTier.Custom(plan)
        }

        fun from(json: JsonElement): ScriptOutput {
            val output = json as? JsonObject ?: throw Strict.Wrong("the output")
            return ScriptOutput(
                quotas = Strict.objects(output, "quotas")?.map(::quota),
                notes = Strict.objects(output, "notes")?.map {
                    Note(Strict.requireText(it, "group"), Strict.requireText(it, "text"), Strict.text(it, "label"))
                },
                plan = Strict.text(output, "plan"),
                cost = Strict.objectOrNull(output, "cost")?.let(::cost),
                account = Strict.objectOrNull(output, "account")?.let {
                    Account(Strict.text(it, "email"), Strict.text(it, "organization"), Strict.text(it, "loginMethod"))
                },
                error = output["error"]?.takeUnless { it is JsonNull }?.let(ErrorRef::from),
            )
        }

        private fun quota(json: JsonObject): Quota {
            val type = QuotaKind.parse(Strict.requireText(json, "type")) ?: throw Strict.Wrong("type")
            val percent = Strict.number(json, "percentRemaining")
            val money = Strict.objectOrNull(json, "left")
            val left = when {
                percent != null && money == null -> Left.Share(percent)
                percent == null && money != null -> {
                    val currency = Strict.text(money, "currency") ?: "USD"
                    if (currency.isBlank()) throw Strict.Wrong("left.currency")
                    Left.Balance(
                        Money(money(money["money"]), currency),
                        money["of"]?.takeUnless { it is JsonNull }?.let { Money(money(it), currency) },
                    )
                }
                else -> throw Strict.Wrong("A quota must contain exactly one of percentRemaining or left")
            }
            return Quota(
                type = type,
                name = Strict.text(json, "name"),
                left = left,
                resetsAt = Strict.number(json, "resetsAt"),
                resetText = Strict.text(json, "resetText"),
                windowSeconds = Strict.number(json, "windowSeconds"),
                group = Strict.text(json, "group"),
            )
        }

        private fun cost(json: JsonObject): Cost = Cost(
            kind = Strict.text(json, "kind")?.let {
                when (it) {
                    "apiCost" -> CostRule.Kind.API_COST
                    "extraUsage" -> CostRule.Kind.EXTRA_USAGE
                    else -> throw Strict.Wrong("cost.kind")
                }
            },
            usedNanos = money(json["used"] ?: throw Strict.Wrong("cost.used")),
            limitNanos = json["limit"]?.takeUnless { it is JsonNull }?.let(::money),
            apiDurationSeconds = Strict.number(json, "apiDurationSeconds"),
            resetsAt = Strict.number(json, "resetsAt"),
            resetText = Strict.text(json, "resetText"),
            lines = Strict.objects(json, "lines")?.map {
                CostLine(Strict.requireText(it, "label"), money(it["used"] ?: throw Strict.Wrong("line.used")), Strict.text(it, "detail"))
            },
        )

        /** `"12.50"` or `12.5`, read as exact nano-units from its text. */
        private fun money(json: JsonElement?): Long {
            val primitive = json as? JsonPrimitive ?: throw Strict.Wrong("an amount")
            val text = when {
                primitive is JsonNull -> throw Strict.Wrong("an amount")
                primitive.isString -> primitive.content
                primitive.booleanOrNull != null -> throw Strict.Wrong("an amount")
                // A number reads through its double, as Swift's `Double` decoding does.
                else -> primitive.content.toDouble().toString()
            }
            return DecimalMoney.nanos(text) ?: throw Strict.Wrong("Not an amount: $text")
        }
    }
}

/** Typed reads of a decoded JSON object: absent or null is null, the wrong shape throws. */
internal object Strict {
    class Wrong(what: String) : IllegalArgumentException("$what has the wrong shape")

    private fun present(json: JsonObject, key: String): JsonElement? = json[key]?.takeUnless { it is JsonNull }

    fun text(json: JsonObject, key: String): String? = present(json, key)?.let {
        (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.content ?: throw Wrong(key)
    }

    fun requireText(json: JsonObject, key: String): String = text(json, key) ?: throw Wrong(key)

    fun number(json: JsonObject, key: String): Double? = present(json, key)?.let {
        (it as? JsonPrimitive)?.takeIf { p -> !p.isString && p.booleanOrNull == null }?.content?.toDoubleOrNull() ?: throw Wrong(key)
    }

    fun requireNumber(json: JsonObject, key: String): Double = number(json, key) ?: throw Wrong(key)

    fun integer(json: JsonObject, key: String): Long? = number(json, key)?.let {
        if (it == kotlin.math.floor(it) && kotlin.math.abs(it) < 9.0e18) it.toLong() else throw Wrong(key)
    }

    fun objectOrNull(json: JsonObject, key: String): JsonObject? = present(json, key)?.let { it as? JsonObject ?: throw Wrong(key) }

    fun objects(json: JsonObject, key: String): List<JsonObject>? = present(json, key)?.let { list ->
        (list as? JsonArray ?: throw Wrong(key)).map { it as? JsonObject ?: throw Wrong(key) }
    }
}
