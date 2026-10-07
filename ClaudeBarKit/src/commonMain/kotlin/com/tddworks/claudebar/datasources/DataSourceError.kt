package com.tddworks.claudebar.datasources

import com.tddworks.claudebar.quotas.UsageError

/**
 * A data source's failure, naming the step that failed — *Couldn't read your key* ·
 * *Couldn't connect* · *Couldn't find the numbers* — because each sends the person somewhere
 * different. Never carries a secret or a response body.
 */
public class DataSourceError(val step: Step, val reason: UsageError) : Exception(reason.message) {
    enum class Step { LOOKUP, FETCH, MAPPING }

    override fun equals(other: Any?) = other is DataSourceError && other.step == step && other.reason == reason
    override fun hashCode() = step.hashCode() * 31 + reason.hashCode()
    override fun toString() = "DataSourceError(${step.name.lowercase()}, $reason)"

    companion object {
        /** Any error thrown inside a step, keeping a `UsageError` as it is. */
        fun wrap(error: Throwable, step: Step): DataSourceError = when (error) {
            is DataSourceError -> error
            is UsageError -> DataSourceError(step, error)
            else -> DataSourceError(step, UsageError.ExecutionFailed(error.message ?: error.toString()))
        }
    }
}
