package com.tddworks.claudebar.quotas

/**
 * The kind of quota tracked. Knows its own names and its persisted key, which must
 * stay byte-for-byte what earlier versions saved.
 */
sealed class QuotaType {
    /** Rolling 5-hour session limit. */
    data object Session : QuotaType()

    /** Rolling 7-day weekly limit. */
    data object Weekly : QuotaType()

    /** A model's own limit ("opus", "sonnet"). */
    data class ModelSpecific(val name: String) : QuotaType()

    /** A named limit ("MCP Usage", "Monthly"). */
    data class TimeLimit(val name: String) : QuotaType()

    /** Human-readable name. */
    val displayName: String
        get() = when (this) {
            Session -> "Session"
            Weekly -> "Weekly"
            is ModelSpecific -> name.capitalizedWords()
            is TimeLimit -> name
        }

    /** Compact label for the menu bar ("5h", "7d"). */
    val shortLabel: String
        get() = when (this) {
            Session -> "5h"
            Weekly -> "7d"
            is ModelSpecific -> name.capitalizedWords()
            is TimeLimit -> name
        }

    /** Stable key used for persisted quota selection. */
    val quotaKey: String
        get() = when (this) {
            Session -> "session"
            Weekly -> "weekly"
            is ModelSpecific -> "model:$name"
            is TimeLimit -> "time:$name"
        }

    /**
     * The window a quota of this name USUALLY has — a convention a data source may
     * state as its own word. Pace never assumes it (CANONICAL_MODEL §5).
     */
    val conventionalWindow: QuotaDuration
        get() = when (this) {
            Session -> QuotaDuration.Hours(5)
            Weekly -> QuotaDuration.Days(7)
            is ModelSpecific -> QuotaDuration.Days(7)
            is TimeLimit -> if (name.equals("Monthly", ignoreCase = true)) QuotaDuration.Days(30) else QuotaDuration.Days(7)
        }

    /** The model name of a model-specific quota. */
    val modelName: String?
        get() = (this as? ModelSpecific)?.name

    companion object {
        /** The quota type a persisted key was saved from, or null. */
        fun fromQuotaKey(quotaKey: String): QuotaType? = when {
            quotaKey == "session" -> Session
            quotaKey == "weekly" -> Weekly
            quotaKey.startsWith("model:") -> quotaKey.removePrefix("model:").takeIf { it.isNotEmpty() }?.let(::ModelSpecific)
            quotaKey.startsWith("time:") -> quotaKey.removePrefix("time:").takeIf { it.isNotEmpty() }?.let(::TimeLimit)
            else -> null
        }
    }
}

/** Foundation's `capitalized`: a letter after a non-letter is upper, after a letter lower. */
internal fun String.capitalizedWords(): String {
    val out = StringBuilder(length)
    var previousIsLetter = false
    for (c in this) {
        out.append(if (c.isLetter()) (if (previousIsLetter) c.lowercaseChar() else c.uppercaseChar()) else c)
        previousIsLetter = c.isLetter()
    }
    return out.toString()
}
