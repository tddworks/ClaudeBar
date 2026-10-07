package com.tddworks.claudebar.quotas

/** The length of a quota window. */
sealed class QuotaDuration {
    data class Hours(val hours: Int) : QuotaDuration() {
        override fun toString(): String = "$hours hour${if (hours == 1) "" else "s"}"
    }

    data class Days(val days: Int) : QuotaDuration() {
        override fun toString(): String = "$days day${if (days == 1) "" else "s"}"
    }

    /** The duration in seconds. */
    val seconds: Double
        get() = when (this) {
            is Hours -> hours * 3600.0
            is Days -> days * 24 * 3600.0
        }
}
