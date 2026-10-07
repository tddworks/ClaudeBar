package com.tddworks.claudebar.monitoring

import kotlin.math.abs

/**
 * How often the menu-bar number refreshes in the background. *Off* refreshes only when the
 * popover opens. No option is under a minute (energy, #67); ten minutes is the default (#204).
 */
internal enum class RefreshInterval(
    /** The poll interval in seconds; null when refresh is off. */
    val seconds: Int?,
    /** What Settings' picker says. */
    val label: String,
) {
    OFF(null, "Off"),
    ONE_MINUTE(60, "1 min"),
    FIVE_MINUTES(300, "5 min"),
    TEN_MINUTES(600, "10 min"),
    FIFTEEN_MINUTES(900, "15 min"),
    ;

    /** Background refresh runs for every option but off. */
    val isEnabled: Boolean get() = this != OFF

    companion object {
        /**
         * The option from the old pair `backgroundSyncEnabled` + `backgroundSyncInterval`, so
         * settings.json stays readable: disabled is off; otherwise the saved seconds snap to the
         * nearest option, never under a minute (30 → 1 min, 120 → 1 min, 300 → 5 min).
         */
        fun migrating(enabled: Boolean, storedSeconds: Double): RefreshInterval {
            if (!enabled) return OFF
            return listOf(ONE_MINUTE, FIVE_MINUTES, TEN_MINUTES, FIFTEEN_MINUTES)
                .minByOrNull { abs((it.seconds ?: 0) - storedSeconds) } ?: ONE_MINUTE
        }
    }
}
