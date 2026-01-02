package com.tddworks.claudebar.domain.model

import kotlin.time.Duration
import kotlin.time.Duration.Companion.days
import kotlin.time.Duration.Companion.hours

/**
 * Represents the type of usage quota being tracked.
 * Rich domain model with behavior - knows its own display name and duration.
 */
sealed class QuotaType {
    /** Rolling 5-hour session limit */
    data object Session : QuotaType()

    /** Rolling 7-day weekly limit */
    data object Weekly : QuotaType()

    /** Model-specific limit (e.g., "opus", "sonnet") */
    data class ModelSpecific(val modelName: String) : QuotaType()

    /** Generic time-based limit (e.g., "MCP Usage") */
    data class TimeLimit(val name: String) : QuotaType()

    /** Human-readable display name for this quota type */
    val displayName: String
        get() = when (this) {
            is Session -> "Session"
            is Weekly -> "Weekly"
            is ModelSpecific -> modelName.replaceFirstChar { it.uppercase() }
            is TimeLimit -> name.replaceFirstChar { it.uppercase() }
        }

    /** The duration of the quota window */
    val duration: Duration
        get() = when (this) {
            is Session -> 5.hours
            is Weekly -> 7.days
            is ModelSpecific -> 7.days // Model-specific limits typically follow weekly windows
            is TimeLimit -> 7.days // Generic time limits default to weekly
        }

    /** The model name if this is a model-specific quota, null otherwise */
    val modelNameOrNull: String?
        get() = (this as? ModelSpecific)?.modelName
}
