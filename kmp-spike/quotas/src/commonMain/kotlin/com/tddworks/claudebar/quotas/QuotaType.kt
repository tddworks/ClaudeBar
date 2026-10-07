package com.tddworks.claudebar.quotas

/** The kind of quota — a port of QuotaType.swift; persisted keys must match the Swift ones byte for byte. */
sealed interface QuotaType {
    data object Session : QuotaType
    data object Weekly : QuotaType
    data class ModelSpecific(val modelName: String) : QuotaType
    data class TimeLimit(val name: String) : QuotaType

    val displayName: String
        get() = when (this) {
            Session -> "Session"
            Weekly -> "Weekly"
            is ModelSpecific -> modelName.capitalizedWords()
            is TimeLimit -> name
        }

    val quotaKey: String
        get() = when (this) {
            Session -> "session"
            Weekly -> "weekly"
            is ModelSpecific -> "model:$modelName"
            is TimeLimit -> "time:$name"
        }

    companion object {
        fun fromQuotaKey(quotaKey: String): QuotaType? = when {
            quotaKey == "session" -> Session
            quotaKey == "weekly" -> Weekly
            quotaKey.startsWith("model:") -> quotaKey.removePrefix("model:").takeIf { it.isNotEmpty() }?.let(::ModelSpecific)
            quotaKey.startsWith("time:") -> quotaKey.removePrefix("time:").takeIf { it.isNotEmpty() }?.let(::TimeLimit)
            else -> null
        }
    }
}

/** Swift's `String.capitalized`: the first letter of each word upper, the rest lower. */
private fun String.capitalizedWords(): String =
    split(" ").joinToString(" ") { word -> word.lowercase().replaceFirstChar { it.uppercaseChar() } }
