package com.tddworks.claudebar.datasources.logs

import com.tddworks.claudebar.datasources.DefinitionError
import com.tddworks.claudebar.datasources.requireString
import com.tddworks.claudebar.diagnostics.AppLog
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * What a token costs, from a price file shipped beside a definition — data, so a price
 * change edits the file, never Kotlin. Amounts are decimal texts, kept exact in nanos.
 *
 * A model is priced by the first rule that knows it: its exact id, the longest id it starts
 * with (or that starts with it), a family its name contains, a free family (a local,
 * open-weight model), an unpriced model on a local route, and otherwise the fallback — a
 * hedge for models newer than the file, never zero by omission.
 */
internal data class PriceList(
    /** Tokens per price — prices are per million when 1000000. */
    val per: NanoAmount.Per,
    val models: List<Model>,
    val families: List<Family>,
    /** Names, matched as lowercased substrings, of model families nobody bills per token. */
    val free: List<String>,
    val otherwise: Price,
) {
    data class Price(
        val input: NanoAmount,
        val output: NanoAmount,
        val cacheWrite: NanoAmount,
        /** A write kept an hour; unset is the five-minute price. */
        val cacheWrite1h: NanoAmount? = null,
        val cacheRead: NanoAmount,
    ) {
        companion object {
            val FREE = Price(NanoAmount.ZERO, NanoAmount.ZERO, NanoAmount.ZERO, NanoAmount.ZERO, NanoAmount.ZERO)

            fun from(json: JsonObject, where: String) = Price(
                input = amount(json, "input", where),
                output = amount(json, "output", where),
                cacheWrite = amount(json, "cacheWrite", where),
                cacheWrite1h = if ("cacheWrite1h" in json) amount(json, "cacheWrite1h", where) else null,
                cacheRead = amount(json, "cacheRead", where),
            )
        }
    }

    data class Model(val id: String, val price: Price)

    /** A name that contains [contains] is priced as the model [priceAs]. */
    data class Family(val contains: String, val priceAs: String)

    /**
     * @param servedLocally the route is on this Mac. Only consulted for names the list doesn't
     *   price: a local route says nothing about which listed model was billed.
     */
    fun price(model: String, servedLocally: Boolean = false): Price {
        models.firstOrNull { it.id == model }?.let { return it.price }
        models.filter { model.startsWith(it.id) }.maxByOrNull { it.id.length }?.let { return it.price }
        models.filter { it.id.startsWith(model) }.minByOrNull { it.id.length }?.let { return it.price }
        families.firstOrNull { model.contains(it.contains) }?.let { family ->
            models.firstOrNull { it.id == family.priceAs }?.let { return it.price }
        }
        val name = model.lowercase()
        if (free.any { name.contains(it) } || servedLocally) return Price.FREE
        return otherwise
    }

    fun cost(record: LogRecord, servedLocally: Boolean = false): NanoAmount {
        val price = price(record.model ?: "", servedLocally)
        return price.input.forTokens(record.input, per) +
            price.output.forTokens(record.output, per) +
            price.cacheWrite.forTokens(record.cacheWrite - record.cacheWrite1h, per) +
            (price.cacheWrite1h ?: price.cacheWrite).forTokens(record.cacheWrite1h, per) +
            price.cacheRead.forTokens(record.cacheRead, per)
    }

    /** What cache reads saved: their tokens at the input price, less what they cost. */
    fun savings(record: LogRecord, servedLocally: Boolean = false): NanoAmount {
        val price = price(record.model ?: "", servedLocally)
        return (price.input - price.cacheRead).forTokens(record.cacheRead, per)
    }

    companion object {
        /** The price file [file], or null — logged — when it is missing or malformed. */
        fun load(file: String, scripts: (String) -> String?): PriceList? {
            val text = scripts(file) ?: run {
                AppLog.probes.error("Usage history: price file '$file' is missing")
                return null
            }
            return try {
                from(Json.parseToJsonElement(text))
            } catch (error: Exception) {
                AppLog.probes.error("Usage history: price file '$file' is malformed: ${error.message}")
                null
            }
        }

        fun from(json: JsonElement): PriceList {
            val root = json as? JsonObject ?: throw DefinitionError("a price file is an object")
            val per = (root["per"] as? JsonPrimitive)?.let { primitive ->
                if (primitive.isString) throw DefinitionError("per is a number")
                NanoAmount.per(primitive.content) ?: throw DefinitionError("per is a positive amount")
            } ?: NanoAmount.Per(1, 1)
            return PriceList(
                per = per,
                models = objects(root, "models").map { Model(it.requireString("id", "models"), Price.from(it, "models")) },
                families = objects(root, "families").map {
                    Family(it.requireString("contains", "families"), it.requireString("as", "families"))
                },
                free = (root["free"] as? JsonArray)?.map {
                    (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.content ?: throw DefinitionError("free holds names")
                } ?: emptyList(),
                otherwise = Price.from(root["otherwise"] as? JsonObject ?: throw DefinitionError("a price file needs otherwise"), "otherwise"),
            )
        }

        private fun objects(root: JsonObject, key: String): List<JsonObject> = when (val value = root[key]) {
            null -> emptyList()
            is JsonArray -> value.map { it as? JsonObject ?: throw DefinitionError("$key holds objects") }
            else -> throw DefinitionError("$key is a list")
        }

        /** `"0.30"` or `0.3`, read exactly from its text. */
        private fun amount(json: JsonObject, key: String, where: String): NanoAmount {
            val primitive = json[key] as? JsonPrimitive ?: throw DefinitionError("$where needs \"$key\"")
            return RecordShape.amount(primitive) ?: throw DefinitionError("$where.$key is not an amount")
        }
    }
}
