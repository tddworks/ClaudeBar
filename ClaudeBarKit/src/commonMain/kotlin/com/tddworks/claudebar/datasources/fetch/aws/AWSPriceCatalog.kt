package com.tddworks.claudebar.datasources.fetch.aws

import com.tddworks.claudebar.datasources.PriceCatalog
import com.tddworks.claudebar.diagnostics.AppLog
import kotlinx.atomicfu.locks.SynchronizedObject
import kotlinx.atomicfu.locks.synchronized
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** A model's prices per million tokens, as exact decimal texts (`"3"`, `"0.8"`). */
internal data class PricedModel(
    val id: String,
    val displayName: String,
    val vendor: String,
    val inputPerMillion: String,
    val outputPerMillion: String,
)

/** Where a model's prices come from — the price list API with its fallbacks; a fake in tests. */
internal interface ModelPricing {
    /** Throws when the model has no price. */
    suspend fun model(id: String): PricedModel
}

internal class PricingError(message: String) : Exception(message)

/**
 * The AWS price list as a [PriceCatalog]: per million tokens, as exact decimal texts, with the
 * model's name and vendor. Only the model service's list is known; any other has no prices.
 */
internal class AWSPriceCatalog(private val pricing: ModelPricing) : PriceCatalog {
    override suspend fun prices(service: String, ids: List<String>): Map<String, Map<String, String>> {
        if (service != MODEL_SERVICE) return emptyMap()
        val prices = mutableMapOf<String, Map<String, String>>()
        for (id in ids) {
            val model = try {
                pricing.model(id)
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                continue
            }
            prices[id] = mapOf(
                "input" to model.inputPerMillion, "output" to model.outputPerMillion, "per" to "1000000",
                "name" to model.displayName, "vendor" to model.vendor,
            )
        }
        return prices
    }

    companion object {
        /** The price list's service code for the hosted models a `cloudWatch` fetch prices. */
        const val MODEL_SERVICE = "AmazonBedrock"
    }
}

/**
 * Prices from the AWS Price List API (`GetProducts`, in us-east-1, with the default
 * credentials), kept for a day. When the API can't answer: the bundled table, else the model
 * at no cost, so it still shows by name.
 */
internal class PriceListModelPricing(
    private val caller: AWSCaller,
    private val now: () -> Double,
) : ModelPricing {
    private val lock = SynchronizedObject()
    private val cache = mutableMapOf<String, PricedModel>()
    private var cachedAt: Double? = null

    override suspend fun model(id: String): PricedModel {
        cached(id)?.let { return it }
        return try {
            fetch(id).also(::remember)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            AppLog.probes.info("AWS Pricing API unavailable, using bundled defaults: ${error.message}")
            BundledModelPrices.model(id)
                ?: PricedModel(id, ModelNames.displayName(id), ModelNames.vendor(id), "0", "0")
        }
    }

    private fun cached(id: String): PricedModel? = synchronized(lock) {
        val at = cachedAt
        if (at != null && now() - at > CACHE_SECONDS) {
            cache.clear()
            cachedAt = null
            return@synchronized null
        }
        cache[id]
    }

    private fun remember(model: PricedModel) = synchronized(lock) {
        cache[model.id] = model
        if (cachedAt == null) cachedAt = now()
    }

    private suspend fun fetch(id: String): PricedModel {
        val request = buildJsonObject {
            put("Filters", buildJsonArray {
                add(filter("ServiceCode", AWSPriceCatalog.MODEL_SERVICE))
                add(filter("modelId", id))
            })
            put("MaxResults", 10)
            put("ServiceCode", AWSPriceCatalog.MODEL_SERVICE)
        }
        // The Price List API answers only in us-east-1 and ap-south-1.
        val response = caller.send(
            "api.pricing.us-east-1.amazonaws.com", "us-east-1", "pricing", null,
            listOf("Content-Type" to "application/x-amz-json-1.1", "X-Amz-Target" to "AWSPriceListService.GetProducts"),
            request.toString().encodeToByteArray(),
        )
        val json = runCatching { Json.parseToJsonElement(response.text) as? JsonObject }.getOrNull()
        val status = response.status ?: 0
        if (status !in 200..299) {
            throw AWSServiceError(status, json?.text("__type")?.substringAfterLast('#'), json?.text("message") ?: json?.text("Message"))
        }
        val first = (json?.get("PriceList") as? JsonArray)?.firstOrNull() as? JsonPrimitive
            ?: throw PricingError("No pricing found for $id")
        return parse(first.content, id)
    }

    /** Input and output prices out of a price list product: each dimension's USD, per million by its unit. */
    internal fun parse(product: String, id: String): PricedModel {
        val json = runCatching { Json.parseToJsonElement(product) as? JsonObject }.getOrNull()
        val onDemand = (json?.get("terms") as? JsonObject)?.get("OnDemand") as? JsonObject
            ?: throw PricingError("Invalid pricing response")
        var input = "0"
        var output = "0"
        for (term in onDemand.values) {
            val dimensions = (term as? JsonObject)?.get("priceDimensions") as? JsonObject ?: continue
            for (dimension in dimensions.values) {
                val fields = dimension as? JsonObject ?: continue
                val usd = (fields["pricePerUnit"] as? JsonObject)?.text("USD") ?: continue
                val description = fields.text("description")?.lowercase() ?: continue
                val raw = DecimalText.normalized(usd) ?: "0"
                val unit = fields.text("unit")?.lowercase().orEmpty()
                val perMillion = when {
                    "1m" in unit || "million" in unit -> raw
                    "1k" in unit || "thousand" in unit -> DecimalText.shifted(raw, 3)
                    else -> DecimalText.shifted(raw, 6)
                }
                if ("input" in description) input = perMillion else if ("output" in description) output = perMillion
            }
        }
        return PricedModel(id, ModelNames.displayName(id), ModelNames.vendor(id), input, output)
    }

    private fun filter(field: String, value: String) = buildJsonObject {
        put("Field", field)
        put("Type", "TERM_MATCH")
        put("Value", value)
    }

    private fun JsonObject.text(key: String) = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content

    private companion object {
        const val CACHE_SECONDS = 86_400.0
    }
}

/** A model's name and vendor read from its id, `us.acme.model-name-20250101-v1:0`. */
internal object ModelNames {
    /** Cross-region inference ids carry a geography first: `us.` `eu.` … */
    private val regionalPrefix = Regex("^(us|eu|ap|sa|ca|me|af)\\.")

    fun baseId(id: String) = id.replace(regionalPrefix, "")

    fun displayName(id: String): String {
        BundledModelPrices.model(id)?.let { return it.displayName }
        val parts = baseId(id).split('.').filter { it.isNotEmpty() }
        if (parts.size < 2) return id
        return parts[1].replace(Regex("-v\\d+:\\d+$"), "").replace(Regex("-\\d{8}"), "").replace("-", " ")
            .split(' ').joinToString(" ") { word -> word.lowercase().replaceFirstChar { it.uppercaseChar() } }
    }

    fun vendor(id: String): String {
        val vendor = baseId(id).split('.').firstOrNull { it.isNotEmpty() } ?: return "Unknown"
        return VENDORS[vendor.lowercase()] ?: vendor.lowercase().replaceFirstChar { it.uppercaseChar() }
    }

    private val VENDORS = mapOf(
        "anthropic" to "Anthropic", "amazon" to "Amazon", "meta" to "Meta", "mistral" to "Mistral AI",
        "cohere" to "Cohere", "ai21" to "AI21 Labs", "stability" to "Stability AI",
    )
}

/** Exact decimal texts, so a price is never rounded through a Double. */
internal object DecimalText {
    private val number = Regex("""^([+-]?)(\d*)(?:\.(\d*))?(?:[eE]([+-]?\d+))?$""")

    /** `"3.00"` → `"3"`, `"0.80"` → `"0.8"`; null when it isn't a number. */
    fun normalized(text: String): String? = parse(text.trim())?.let { (sign, digits, scale) -> render(sign, digits, scale) }

    /** [text] times 10^[places]. */
    fun shifted(text: String, places: Int): String =
        parse(text)?.let { (sign, digits, scale) -> render(sign, digits, scale - places) } ?: "0"

    /** Sign, digits and how many of them are after the point. */
    private fun parse(text: String): Triple<String, String, Int>? {
        val match = number.matchEntire(text) ?: return null
        val (sign, whole, fraction, exponent) = match.destructured
        if (whole.isEmpty() && fraction.isEmpty()) return null
        return Triple(sign, whole + fraction, fraction.length - (exponent.toIntOrNull() ?: 0))
    }

    private fun render(sign: String, digits: String, scale: Int): String {
        var all = digits
        var after = scale
        if (after < 0) { all += "0".repeat(-after); after = 0 }
        if (all.length <= after) all = "0".repeat(after - all.length + 1) + all
        val whole = all.dropLast(after).trimStart('0').ifEmpty { "0" }
        val fraction = all.takeLast(after).trimEnd('0')
        val text = if (fraction.isEmpty()) whole else "$whole.$fraction"
        return if (sign == "-" && text != "0") "-$text" else text
    }
}

/**
 * Bundled prices for common hosted models, the fallback when the price list can't answer. A
 * regional id prices like its base model; a version suffix (`:0`) may be left off.
 */
internal object BundledModelPrices {
    fun model(id: String): PricedModel? {
        val base = ModelNames.baseId(id)
        val model = MODELS[base] ?: MODELS[base.replace(Regex(":\\d+$"), "")] ?: return null
        return model.copy(id = id)
    }

    private fun priced(id: String, name: String, vendor: String, input: String, output: String) =
        id to PricedModel(id, name, vendor, input, output)

    private val MODELS = mapOf(
        priced("anthropic.claude-opus-4-5-20251101-v1:0", "Claude Opus 4.5", "Anthropic", "15", "75"),
        priced("anthropic.claude-haiku-4-5-20251001-v1:0", "Claude Haiku 4.5", "Anthropic", "1", "5"),
        priced("anthropic.claude-sonnet-4-20250514-v1:0", "Claude Sonnet 4", "Anthropic", "3", "15"),
        priced("anthropic.claude-3-5-sonnet-20241022-v2:0", "Claude 3.5 Sonnet v2", "Anthropic", "3", "15"),
        priced("anthropic.claude-3-5-sonnet-20240620-v1:0", "Claude 3.5 Sonnet", "Anthropic", "3", "15"),
        priced("anthropic.claude-3-5-haiku-20241022-v1:0", "Claude 3.5 Haiku", "Anthropic", "0.8", "4"),
        priced("anthropic.claude-3-opus-20240229-v1:0", "Claude 3 Opus", "Anthropic", "15", "75"),
        priced("anthropic.claude-3-sonnet-20240229-v1:0", "Claude 3 Sonnet", "Anthropic", "3", "15"),
        priced("anthropic.claude-3-haiku-20240307-v1:0", "Claude 3 Haiku", "Anthropic", "0.25", "1.25"),
        priced("amazon.titan-text-premier-v1:0", "Titan Text Premier", "Amazon", "0.5", "1.5"),
        priced("amazon.titan-text-express-v1", "Titan Text Express", "Amazon", "0.2", "0.6"),
        priced("amazon.titan-text-lite-v1", "Titan Text Lite", "Amazon", "0.15", "0.2"),
        priced("meta.llama3-2-90b-instruct-v1:0", "Llama 3.2 90B", "Meta", "0.72", "0.72"),
        priced("meta.llama3-2-11b-instruct-v1:0", "Llama 3.2 11B", "Meta", "0.16", "0.16"),
        priced("meta.llama3-2-3b-instruct-v1:0", "Llama 3.2 3B", "Meta", "0.1", "0.1"),
        priced("meta.llama3-2-1b-instruct-v1:0", "Llama 3.2 1B", "Meta", "0.1", "0.1"),
        priced("meta.llama3-1-405b-instruct-v1:0", "Llama 3.1 405B", "Meta", "2.4", "2.4"),
        priced("meta.llama3-1-70b-instruct-v1:0", "Llama 3.1 70B", "Meta", "0.72", "0.72"),
        priced("meta.llama3-1-8b-instruct-v1:0", "Llama 3.1 8B", "Meta", "0.22", "0.22"),
        priced("mistral.mistral-large-2407-v1:0", "Mistral Large", "Mistral AI", "3", "9"),
        priced("mistral.mistral-small-2402-v1:0", "Mistral Small", "Mistral AI", "0.1", "0.3"),
        priced("mistral.mixtral-8x7b-instruct-v0:1", "Mixtral 8x7B", "Mistral AI", "0.45", "0.7"),
    )
}
