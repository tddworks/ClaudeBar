package com.tddworks.claudebar.quotas

/**
 * Why there is no usage — the reason a `DataSourceError` carries with the step that failed.
 * One closed sum; its [tag]s are what a definition's `fallbackOn` and `recover` name.
 * Thrown inside the SDK; across the bridge it travels as a value (MODULAR_DESIGN §5).
 */
internal sealed class UsageError(message: String) : Exception(message) {
    /** The name a definition uses for this failure. */
    abstract val tag: String

    class CliNotFound(val binary: String) : UsageError("CLI not found: $binary") {
        override val tag get() = "cliNotFound"
    }

    object AuthenticationRequired : UsageError("Authentication required. Please log in.") {
        override val tag get() = "authenticationRequired"
    }

    /** Equal to any other expired session: the hint is advice, not identity. */
    class SessionExpired(val hint: String? = null) :
        UsageError(if (hint != null) "Session expired. $hint" else "Session expired. Please log in again.") {
        override val tag get() = "sessionExpired"
    }

    class ParseFailed(val reason: String) : UsageError("Failed to parse output: $reason") {
        override val tag get() = "parseFailed"
    }

    object Timeout : UsageError("Request timed out") {
        override val tag get() = "timeout"
    }

    object NoData : UsageError("No usage data available") {
        override val tag get() = "noData"
    }

    object UpdateRequired : UsageError("CLI update required") {
        override val tag get() = "updateRequired"
    }

    object FolderTrustRequired : UsageError("Please trust this folder in Claude CLI") {
        override val tag get() = "folderTrustRequired"
    }

    class ExecutionFailed(val reason: String) : UsageError(reason) {
        override val tag get() = "executionFailed"
    }

    object SubscriptionRequired : UsageError("Subscription required for usage data") {
        override val tag get() = "subscriptionRequired"
    }

    /** HTTP 429: not before [retryAtSeconds] (Unix seconds). */
    class RateLimited(val retryAtSeconds: Double) : UsageError("Rate limited") {
        override val tag get() = "rateLimited"
    }

    override fun equals(other: Any?): Boolean = other is UsageError && other.tag == tag && when (this) {
        is CliNotFound -> binary == (other as CliNotFound).binary
        is ParseFailed -> reason == (other as ParseFailed).reason
        is ExecutionFailed -> reason == (other as ExecutionFailed).reason
        is RateLimited -> retryAtSeconds == (other as RateLimited).retryAtSeconds
        else -> true
    }

    override fun hashCode(): Int = tag.hashCode()

    override fun toString(): String = "UsageError.$tag($message)"
}
