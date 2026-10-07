package com.tddworks.claudebar.datasources.mapping

import com.tddworks.claudebar.datasources.DefinitionError
import com.tddworks.claudebar.datasources.DefinitionJson
import com.tddworks.claudebar.datasources.decoding
import com.tddworks.claudebar.datasources.singleTag
import com.tddworks.claudebar.datasources.tagged
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.KSerializer
import kotlinx.serialization.KeepGeneratedSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.encodeToJsonElement

/**
 * WHAT THE BYTES SAY — *Map fields*. A closed sum, one case per JSON tag: a JSON response is
 * read by paths, a terminal screen by patterns.
 */
@Serializable(with = MappingSerializer::class)
internal sealed class Mapping {
    data class Json(val mapping: JSONMapping) : Mapping()
    data class Text(val mapping: TextMapping) : Mapping()

    /**
     * A format no rule can say — a TUI screen, a money shape — read by a JavaScript file with
     * no file, network or process access.
     */
    data class Script(val mapping: ScriptMapping) : Mapping()

    /** ClaudeBar's own documented output — `quotas[]` and `costUsage` — which an extension's script prints. */
    data object Usage : Mapping()

    companion object {
        val tags = listOf("json", "text", "script", "usage")

        fun from(json: JsonElement): Mapping {
            val tagged = json as? JsonObject ?: throw DefinitionError("mapping is an object with one tag")
            val tag = tagged.singleTag(tags, "mapping")
            val payload = tagged.getValue(tag)
            return decoding("mapping.$tag") {
                when (tag) {
                    "json" -> Json(DefinitionJson.decodeFromJsonElement(payload))
                    "text" -> Text(DefinitionJson.decodeFromJsonElement(payload))
                    "script" -> Script(DefinitionJson.decodeFromJsonElement(payload))
                    else -> if (payload is JsonObject) Usage else throw DefinitionError("mapping.usage is an object")
                }
            }
        }
    }

    fun toJson(): JsonElement = when (this) {
        is Json -> tagged("json", DefinitionJson.encodeToJsonElement(mapping))
        is Text -> tagged("text", DefinitionJson.encodeToJsonElement(mapping))
        is Script -> tagged("script", DefinitionJson.encodeToJsonElement(mapping))
        Usage -> tagged("usage", JsonObject(emptyMap()))
    }
}

internal object MappingSerializer : KSerializer<Mapping> {
    override val descriptor: SerialDescriptor = JsonElement.serializer().descriptor
    override fun deserialize(decoder: Decoder) = Mapping.from((decoder as JsonDecoder).decodeJsonElement())
    override fun serialize(encoder: Encoder, value: Mapping) = (encoder as JsonEncoder).encodeJsonElement(value.toJson())
}

/**
 * `{ "script": { "file": "claude-usage-screen.js", "credential": ["subscriptionType"] } }`. The
 * script defines `read(response, context)` and sees only the credential values named here —
 * never a token.
 */
@Serializable
internal data class ScriptMapping(
    val file: String,
    val credential: List<String> = emptyList(),
    /** `context.values` — typically `{{setting.x}}`; one still holding a template was left blank, and isn't there. */
    val values: Map<String, String> = emptyMap(),
)

// Shared vocabulary

/** Which kind of quota a rule produces — today's `QuotaType`. */
@Serializable
internal enum class QuotaKind {
    @SerialName("session") SESSION,
    @SerialName("weekly") WEEKLY,
    /** A model-specific limit, named by the rule. */
    @SerialName("model") MODEL,
    /** Any other named limit, named by the rule. */
    @SerialName("time") TIME;

    companion object {
        fun parse(text: String): QuotaKind? = when (text) {
            "session" -> SESSION
            "weekly" -> WEEKLY
            "model" -> MODEL
            "time" -> TIME
            else -> null
        }
    }
}

/**
 * A value read from the response: a path, or a constant written in the definition. A list of
 * them means *the first that answers*.
 */
@Serializable(with = ValueRefSerializer::class)
internal sealed class ValueRef {
    data class Path(val path: String) : ValueRef()
    data class Constant(val value: Double) : ValueRef()
}

internal object ValueRefSerializer : KSerializer<ValueRef> {
    override val descriptor: SerialDescriptor = JsonElement.serializer().descriptor
    override fun deserialize(decoder: Decoder) = from((decoder as JsonDecoder).decodeJsonElement())
    override fun serialize(encoder: Encoder, value: ValueRef) = (encoder as JsonEncoder).encodeJsonElement(
        when (value) {
            is ValueRef.Path -> JsonPrimitive(value.path)
            is ValueRef.Constant -> JsonPrimitive(value.value)
        },
    )

    fun from(json: JsonElement): ValueRef {
        val primitive = json as? JsonPrimitive
        if (primitive == null || primitive is JsonNull) throw DefinitionError("a value is a path or a number")
        if (primitive.isString) return ValueRef.Path(primitive.content)
        return primitive.doubleOrNull?.let(ValueRef::Constant) ?: throw DefinitionError("a value is a path or a number")
    }
}

/** When a quota resets, from one of the shapes providers use. */
@Serializable(with = ResetRefSerializer::class)
internal sealed class ResetRef {
    abstract val path: String

    data class EpochSeconds(override val path: String) : ResetRef()
    data class SecondsFromNow(override val path: String) : ResetRef()
    data class Iso8601(override val path: String) : ResetRef()
}

internal object ResetRefSerializer : KSerializer<ResetRef> {
    private val tags = listOf("epochSeconds", "secondsFromNow", "iso8601")
    override val descriptor: SerialDescriptor = JsonElement.serializer().descriptor

    override fun deserialize(decoder: Decoder): ResetRef {
        val json = (decoder as JsonDecoder).decodeJsonElement() as? JsonObject ?: throw DefinitionError("resetsAt is an object with one tag")
        val tag = json.singleTag(tags, "resetsAt")
        val path = json.text(tag, "resetsAt")
        return when (tag) {
            "epochSeconds" -> ResetRef.EpochSeconds(path)
            "secondsFromNow" -> ResetRef.SecondsFromNow(path)
            else -> ResetRef.Iso8601(path)
        }
    }

    override fun serialize(encoder: Encoder, value: ResetRef) = (encoder as JsonEncoder).encodeJsonElement(
        tagged(
            when (value) {
                is ResetRef.EpochSeconds -> "epochSeconds"
                is ResetRef.SecondsFromNow -> "secondsFromNow"
                is ResetRef.Iso8601 -> "iso8601"
            },
            JsonPrimitive(value.path),
        ),
    )
}

/**
 * A window's length — read in the unit the provider reports it in, or a fixed length the
 * provider is known for: `{ "seconds": "limit_window_seconds" }` · `{ "minutes": "windowDurationMins" }` ·
 * `{ "hours": 5 }` · `{ "days": 7 }`. The kernel never guesses one.
 */
@Serializable(with = DurationRefSerializer::class)
internal sealed class DurationRef {
    data class Seconds(val path: String) : DurationRef()
    data class Minutes(val path: String) : DurationRef()
    data class Fixed(val seconds: Double) : DurationRef()
}

internal object DurationRefSerializer : KSerializer<DurationRef> {
    private val scales = mapOf("seconds" to 1.0, "minutes" to 60.0, "hours" to 3600.0, "days" to 86400.0)
    override val descriptor: SerialDescriptor = JsonElement.serializer().descriptor

    override fun deserialize(decoder: Decoder): DurationRef {
        val json = (decoder as JsonDecoder).decodeJsonElement() as? JsonObject ?: throw DefinitionError("window is an object with one tag")
        val tag = json.singleTag(scales.keys.toList(), "window")
        val value = json.getValue(tag) as? JsonPrimitive
        if (value != null && !value.isString && value !is JsonNull) {
            value.doubleOrNull?.let { return DurationRef.Fixed(it * scales.getValue(tag)) }
        }
        val path = json.text(tag, "window")
        // An hours or days path reads as seconds, as it always has.
        return if (tag == "minutes") DurationRef.Minutes(path) else DurationRef.Seconds(path)
    }

    override fun serialize(encoder: Encoder, value: DurationRef) = (encoder as JsonEncoder).encodeJsonElement(
        when (value) {
            is DurationRef.Seconds -> tagged("seconds", JsonPrimitive(value.path))
            is DurationRef.Minutes -> tagged("minutes", JsonPrimitive(value.path))
            is DurationRef.Fixed -> tagged("seconds", JsonPrimitive(value.seconds))
        },
    )
}

/** A quota's name: fixed text (`"Session"`), or read from the response and tidied. */
@OptIn(ExperimentalSerializationApi::class)
@KeepGeneratedSerializer
@Serializable(with = NameRuleSerializer::class)
internal data class NameRule(
    val text: String? = null,
    val firstOf: List<String> = emptyList(),
    /** The first prefix that matches is the one dropped. */
    val dropPrefixes: List<Prefix> = emptyList(),
    /** Only the first word — "Fable 5" → "Fable". */
    val firstWord: Boolean = false,
    val lowercase: Boolean = false,
) {
    /** Strips a prefix (case-insensitively); `capitalize` upper-cases the first letter of what is left. */
    @Serializable
    data class Prefix(val prefix: String, val capitalize: Boolean = false)
}

@OptIn(ExperimentalSerializationApi::class)
internal object NameRuleSerializer : KSerializer<NameRule> {
    override val descriptor: SerialDescriptor = JsonElement.serializer().descriptor

    override fun deserialize(decoder: Decoder): NameRule {
        val json = (decoder as JsonDecoder).decodeJsonElement()
        if (json is JsonPrimitive && json.isString) return NameRule(text = json.content)
        return DefinitionJson.decodeFromJsonElement(NameRule.generatedSerializer(), json)
    }

    override fun serialize(encoder: Encoder, value: NameRule) =
        (encoder as JsonEncoder).encodeJsonElement(DefinitionJson.encodeToJsonElement(NameRule.generatedSerializer(), value))
}

/** The failure a rule reports, as one of today's `UsageError`s. */
@Serializable(with = ErrorRefSerializer::class)
internal sealed class ErrorRef {
    data object AuthenticationRequired : ErrorRef()
    data object UpdateRequired : ErrorRef()
    data object FolderTrustRequired : ErrorRef()
    data object SubscriptionRequired : ErrorRef()
    data object NoData : ErrorRef()
    data class ParseFailed(val reason: String) : ErrorRef()
    data class SessionExpired(val hint: String?) : ErrorRef()
    data class ExecutionFailed(val reason: String) : ErrorRef()

    /** *CLI not found*, naming the CLI the person should install. */
    data class CliNotFound(val name: String) : ErrorRef()

    val usageError: UsageError
        get() = when (this) {
            AuthenticationRequired -> UsageError.AuthenticationRequired
            UpdateRequired -> UsageError.UpdateRequired
            FolderTrustRequired -> UsageError.FolderTrustRequired
            SubscriptionRequired -> UsageError.SubscriptionRequired
            NoData -> UsageError.NoData
            is ParseFailed -> UsageError.ParseFailed(reason)
            is SessionExpired -> UsageError.SessionExpired(hint)
            is ExecutionFailed -> UsageError.ExecutionFailed(reason)
            is CliNotFound -> UsageError.CliNotFound(name)
        }

    fun toJson(): JsonElement = when (this) {
        is ParseFailed -> tagged("parseFailed", JsonPrimitive(reason))
        is SessionExpired -> hint?.let { tagged("sessionExpired", JsonPrimitive(it)) } ?: JsonPrimitive("sessionExpired")
        is ExecutionFailed -> tagged("executionFailed", JsonPrimitive(reason))
        is CliNotFound -> tagged("cliNotFound", JsonPrimitive(name))
        AuthenticationRequired -> JsonPrimitive("authenticationRequired")
        UpdateRequired -> JsonPrimitive("updateRequired")
        FolderTrustRequired -> JsonPrimitive("folderTrustRequired")
        SubscriptionRequired -> JsonPrimitive("subscriptionRequired")
        NoData -> JsonPrimitive("noData")
    }

    companion object {
        private val withText = listOf("parseFailed", "sessionExpired", "executionFailed", "cliNotFound")

        fun from(json: JsonElement): ErrorRef {
            if (json is JsonPrimitive && json.isString) {
                return when (val tag = json.content) {
                    "authenticationRequired" -> AuthenticationRequired
                    "updateRequired" -> UpdateRequired
                    "folderTrustRequired" -> FolderTrustRequired
                    "subscriptionRequired" -> SubscriptionRequired
                    "noData" -> NoData
                    "sessionExpired" -> SessionExpired(null)
                    else -> throw DefinitionError("Unknown error '$tag'")
                }
            }
            val tagged = json as? JsonObject ?: throw DefinitionError("error is a name or an object with one tag")
            val tag = tagged.singleTag(withText, "error")
            val text = tagged.text(tag, "error")
            return when (tag) {
                "parseFailed" -> ParseFailed(text)
                "cliNotFound" -> CliNotFound(text)
                "executionFailed" -> ExecutionFailed(text)
                else -> SessionExpired(text)
            }
        }
    }
}

internal object ErrorRefSerializer : KSerializer<ErrorRef> {
    override val descriptor: SerialDescriptor = JsonElement.serializer().descriptor
    override fun deserialize(decoder: Decoder) = ErrorRef.from((decoder as JsonDecoder).decodeJsonElement())
    override fun serialize(encoder: Encoder, value: ErrorRef) = (encoder as JsonEncoder).encodeJsonElement(value.toJson())
}

// JSON mapping

/** Reads a JSON response by paths — *Used · Remaining · Limit · Resets*. */
@Serializable
internal data class JSONMapping(
    val plan: PlanRule? = null,
    val quotas: List<QuotaRule> = emptyList(),
    /** The first that answers — one rule, or a list of shapes a provider has used over time. */
    @Serializable(with = CostRules::class) val cost: List<CostRule> = emptyList(),
    /** What to do when no quota answered. */
    val whenEmpty: EmptyRule? = null,
    /** The account's email — the first path that answers, `$credential.` included. */
    @Serializable(with = Texts::class) val email: List<String> = emptyList(),
    /** The `parseFailed` reason when the body is JSON but not an object. */
    val notAnObject: String? = null,
)

/** One quota — or, with `each`, one per element of an array or map. */
@Serializable
internal data class QuotaRule(
    val kind: QuotaKind,
    val name: NameRule? = null,
    /** The object the values are read from. */
    val at: String? = null,
    /** Repeat over this array, or this map in key order. */
    val each: String? = null,
    /** Map keys not to repeat over. */
    val skipKeys: List<String> = emptyList(),
    /** Per element, read these sub-objects instead of the element itself. */
    val windows: List<WindowPick> = emptyList(),
    @Serializable(with = ValueRefs::class) val usedPercent: List<ValueRef> = emptyList(),
    @Serializable(with = ValueRefs::class) val leftPercent: List<ValueRef> = emptyList(),
    @Serializable(with = ResetRefs::class) val resetsAt: List<ResetRef> = emptyList(),
    /** The first that answers — what the response states, then a length the provider is known for. */
    @Serializable(with = DurationRefs::class) val window: List<DurationRef> = emptyList(),
    /** Fixed text in place of the reset countdown ("Free plan"). */
    val resetText: String? = null,
    /** With `each`: only the elements where this holds. */
    @SerialName("where") val condition: Match? = null,
    /** Over the limit reads as negative left, as the provider reports it, instead of 0. */
    val overLimit: Boolean = false,
    val countdown: Countdown = Countdown.DAYS,
    /** Skip a quota whose kind and name an earlier rule already produced — the first one wins. */
    val unique: Boolean = false,
    /** Money in place of a percentage; without `of` it is a balance, with no percentage at all. */
    val left: MoneyLeft? = null,
) {
    /** A sub-object to read per element, and the suffix its quota's name gets ("Spark" · "Spark 7d"). */
    @Serializable
    data class WindowPick(val at: String, val suffix: String = "")

    /** `{ "money": "$.remaining", "of": "$.limit", "currency": "USD" }`. */
    @Serializable
    data class MoneyLeft(
        val money: Amount,
        val of: Amount? = null,
        /** ISO 4217; USD when absent. */
        val currency: String? = null,
    )

    /** `days` — "Resets in 2d 5h 30m"; `hours` — "Resets in 53h 30m". */
    @Serializable
    enum class Countdown {
        @SerialName("days") DAYS,
        @SerialName("hours") HOURS,
    }
}

/**
 * The plan badge — "PLUS", "PRO" — from a field (`$credential.` included), upper-cased unless
 * `badges` names it. With `plans`, a value is one of the well-known plans by name, and any
 * other is kept as written.
 */
@OptIn(ExperimentalSerializationApi::class)
@KeepGeneratedSerializer
@Serializable(with = PlanRuleSerializer::class)
internal data class PlanRule(
    val path: String,
    val badges: Map<String, String> = emptyMap(),
    val plans: Map<String, String> = emptyMap(),
)

@OptIn(ExperimentalSerializationApi::class)
internal object PlanRuleSerializer : KSerializer<PlanRule> {
    override val descriptor: SerialDescriptor = JsonElement.serializer().descriptor

    override fun deserialize(decoder: Decoder): PlanRule {
        val json = (decoder as JsonDecoder).decodeJsonElement()
        if (json is JsonPrimitive && json.isString) return PlanRule(json.content)
        return DefinitionJson.decodeFromJsonElement(PlanRule.generatedSerializer(), json)
    }

    override fun serialize(encoder: Encoder, value: PlanRule) =
        (encoder as JsonEncoder).encodeJsonElement(DefinitionJson.encodeToJsonElement(PlanRule.generatedSerializer(), value))
}

/**
 * Money gone — "EXTRA USAGE" or "API COST" — from what is left of a limit, or what was used.
 * The rule answers nothing when `when` does not hold, when nothing was used, or when a limit
 * is present but not money.
 */
@Serializable
internal data class CostRule(
    val kind: Kind = Kind.API_COST,
    @SerialName("when") val condition: Match? = null,
    @Serializable(with = ValueRefs::class) val remaining: List<ValueRef> = emptyList(),
    val used: Amount? = null,
    val limit: Amount? = null,
) {
    @Serializable
    enum class Kind {
        @SerialName("apiCost") API_COST,
        @SerialName("extraUsage") EXTRA_USAGE,
    }
}

/**
 * An amount of money: a number in the currency — `"used"` or a list, the first that answers —
 * or minor units shifted by a number of decimal places, `{ "amount": "used.amount_minor",
 * "decimals": "used.exponent" }`. A negative amount or a fractional or negative `decimals` is not money.
 */
@Serializable(with = AmountSerializer::class)
internal sealed class Amount {
    data class Value(val refs: List<ValueRef>) : Amount()
    data class MinorUnits(val amount: String, val decimals: List<ValueRef>) : Amount()
}

internal object AmountSerializer : KSerializer<Amount> {
    override val descriptor: SerialDescriptor = JsonElement.serializer().descriptor

    override fun deserialize(decoder: Decoder): Amount {
        val json = (decoder as JsonDecoder).decodeJsonElement()
        val amount = ((json as? JsonObject)?.get("amount") as? JsonPrimitive)?.takeIf { it.isString }
        if (amount != null) {
            val decimals = json["decimals"]?.let(ValueRefs::from) ?: emptyList()
            return Amount.MinorUnits(amount.content, decimals)
        }
        return Amount.Value(ValueRefs.from(json))
    }

    override fun serialize(encoder: Encoder, value: Amount) = (encoder as JsonEncoder).encodeJsonElement(
        when (value) {
            is Amount.Value -> ValueRefs.toJson(value.refs)
            is Amount.MinorUnits -> JsonObject(mapOf("amount" to JsonPrimitive(value.amount), "decimals" to ValueRefs.toJson(value.decimals)))
        },
    )
}

/** `{ "path": "kind", "equals": "weekly_scoped" }` — a value in the response equals this JSON value. */
@Serializable
internal data class Match(val path: String, val equals: JsonElement)

/** When nothing answered: fixed quotas if a field says so, otherwise a failure. */
@Serializable
internal data class EmptyRule(
    @SerialName("if") val condition: Condition? = null,
    val quotas: List<QuotaRule> = emptyList(),
    /** The `parseFailed` reason when the condition does not hold. */
    val otherwise: String? = null,
) {
    @Serializable
    data class Condition(val path: String, val equals: String)
}

// Text mapping

/** Reads a terminal screen by patterns: errors first, then each quota's label and the percentage within a few lines of it. */
@Serializable
internal data class TextMapping(
    val errors: List<ErrorRule> = emptyList(),
    val quotas: List<QuotaPattern>,
    /** The `parseFailed` reason when no quota is found. */
    val whenEmpty: String? = null,
) {
    @Serializable
    data class ErrorRule(
        /** Any of these phrases (case-insensitive)… */
        val contains: List<String>,
        /** …and all of these, when given. */
        val alsoContains: List<String> = emptyList(),
        val error: ErrorRef,
    )

    @Serializable
    data class QuotaPattern(
        val kind: QuotaKind,
        val name: String? = null,
        /** The line that names the quota (case-insensitive substring). */
        val label: String,
        /** A regex whose first group is the percentage **left**. */
        val leftPercent: String? = null,
        /** A regex whose first group is the percentage **used**. */
        val usedPercent: String? = null,
        /** How many lines from the label to look. */
        val lookahead: Int = 12,
    )
}

// One value or a list of them — `"used_percent"` or `["$header.x", "used_percent"]` — always written as a list.

internal open class OneOrMany<T>(private val element: KSerializer<T>) : KSerializer<List<T>> {
    override val descriptor: SerialDescriptor = JsonElement.serializer().descriptor

    fun from(json: JsonElement): List<T> = when (json) {
        JsonNull -> emptyList()
        is JsonArray -> json.map { DefinitionJson.decodeFromJsonElement(element, it) }
        else -> listOf(DefinitionJson.decodeFromJsonElement(element, json))
    }

    fun toJson(values: List<T>): JsonElement = JsonArray(values.map { DefinitionJson.encodeToJsonElement(element, it) })

    override fun deserialize(decoder: Decoder) = from((decoder as JsonDecoder).decodeJsonElement())
    override fun serialize(encoder: Encoder, value: List<T>) = (encoder as JsonEncoder).encodeJsonElement(toJson(value))
}

internal object ValueRefs : OneOrMany<ValueRef>(ValueRefSerializer)
internal object ResetRefs : OneOrMany<ResetRef>(ResetRefSerializer)
internal object DurationRefs : OneOrMany<DurationRef>(DurationRefSerializer)
internal object CostRules : OneOrMany<CostRule>(CostRule.serializer())
internal object Texts : OneOrMany<String>(String.serializer())

private fun JsonObject.text(key: String, type: String): String =
    (get(key) as? JsonPrimitive)?.takeIf { it.isString }?.content ?: throw DefinitionError("$type.$key is text")
