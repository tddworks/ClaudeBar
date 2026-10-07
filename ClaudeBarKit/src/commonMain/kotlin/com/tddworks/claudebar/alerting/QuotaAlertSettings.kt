package com.tddworks.claudebar.alerting

import com.tddworks.claudebar.storage.SettingsFile
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull

/** The person's quota-alert percentages in settings.json, under `alerts.thresholds`. */
internal class QuotaAlertSettings(private val settings: SettingsFile) : QuotaAlertSettingsRepository {

    /** Empty when absent, or when anything in the list isn't a whole number (as Swift's `[Int]` read). */
    override fun quotaAlertPercents(): List<Int> {
        val list = settings.read(KEY) as? JsonArray ?: return emptyList()
        return list.map { element ->
            val number = (element as? JsonPrimitive)?.takeUnless { it.isString }?.doubleOrNull
            if (number == null || number != kotlin.math.floor(number) || !number.isFinite()) return emptyList()
            number.toInt()
        }
    }

    override fun setQuotaAlertPercents(percents: List<Int>) =
        settings.write(KEY, JsonArray(percents.map(::JsonPrimitive)))

    private companion object {
        const val KEY = "alerts.thresholds"
    }
}
