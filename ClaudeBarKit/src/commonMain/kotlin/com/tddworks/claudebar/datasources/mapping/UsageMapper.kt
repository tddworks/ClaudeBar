package com.tddworks.claudebar.datasources.mapping

import com.tddworks.claudebar.datasources.MappingFacts
import com.tddworks.claudebar.datasources.Reading
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.quotas.CostUsage
import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageError
import com.tddworks.claudebar.quotas.UsageQuota
import com.tddworks.claudebar.quotas.UsageSnapshot
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject

/**
 * `usage` — ClaudeBar's own documented output, read as extensions always were: a quota's
 * `type` says its kind, its window is the kind's conventional one, and `costUsage` is money
 * spent against a budget.
 */
internal class UsageMapper(private val now: () -> Double) : Reading {
    override fun read(response: Response, facts: MappingFacts, providerId: String): UsageSnapshot {
        val output = runCatching { decode(response.text, providerId) }.getOrNull()
            ?: throw UsageError.ParseFailed("Output is not ClaudeBar's usage JSON")
        if (output.first == null && output.second == null) {
            throw UsageError.ParseFailed("Output has neither quotas nor costUsage")
        }
        return UsageSnapshot(providerId, output.first.orEmpty(), now(), null, null, null, null, output.second, null, null)
    }

    /** The quotas and the cost, each null when absent; throws when a field has the wrong shape. */
    private fun decode(text: String, providerId: String): Pair<List<UsageQuota>?, CostUsage?> {
        val json = Json.parseToJsonElement(text) as JsonObject
        val quotas = Strict.objects(json, "quotas")?.map { quota(it, providerId) }
        val cost = Strict.objectOrNull(json, "costUsage")?.let { cost(it, providerId) }
        return quotas to cost
    }

    private fun quota(json: JsonObject, providerId: String): UsageQuota {
        val type = Strict.requireText(json, "type")
        val kind = when {
            type == "session" -> QuotaType.Session
            type == "weekly" -> QuotaType.Weekly
            type.startsWith("model:") -> QuotaType.ModelSpecific(type.drop(6))
            else -> QuotaType.TimeLimit(type)
        }
        // Dates as `JSONDecoder.iso8601` reads them: no fractional seconds.
        val resetsAt = Strict.text(json, "resetsAt")?.let { iso8601Seconds(it, fractional = false) ?: throw Strict.Wrong("resetsAt") }
        return UsageQuota(
            percentRemaining = Strict.requireNumber(json, "percentRemaining"),
            quotaType = kind,
            providerId = providerId,
            resetsAtSeconds = resetsAt,
            resetText = Strict.text(json, "resetText"),
            windowSeconds = kind.conventionalWindow.seconds,
            dollarRemainingNanos = Strict.number(json, "dollarRemaining")?.let { DecimalMoney.nanos(it) ?: throw Strict.Wrong("dollarRemaining") },
            dollarUsedNanos = null,
            dollarCapNanos = null,
            group = null,
            compactTitle = null,
            menuBarTitle = null,
            currency = null,
        )
    }

    private fun cost(json: JsonObject, providerId: String): CostUsage = CostUsage(
        totalCostNanos = DecimalMoney.nanos(Strict.requireNumber(json, "totalCost")) ?: throw Strict.Wrong("totalCost"),
        budgetNanos = Strict.number(json, "budget")?.let { DecimalMoney.nanos(it) ?: throw Strict.Wrong("budget") },
        apiDuration = Strict.requireNumber(json, "apiDuration"),
        wallDuration = Strict.number(json, "wallDuration") ?: 0.0,
        linesAdded = Strict.integer(json, "linesAdded") ?: 0,
        linesRemoved = Strict.integer(json, "linesRemoved") ?: 0,
        providerId = providerId,
        kind = CostUsage.Kind.API_COST,
        capturedAtSeconds = now(),
        resetsAtSeconds = null,
        resetText = null,
        lines = emptyList(),
    )
}
