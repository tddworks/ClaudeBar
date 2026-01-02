package com.tddworks.claudebar.domain.model

/**
 * Errors that can occur when probing a CLI
 */
sealed class ProbeError : Exception() {
    /** The CLI binary was not found on the system */
    data class CliNotFound(val tool: String) : ProbeError() {
        override val message: String get() = "CLI '$tool' not found on system"
    }

    /** User needs to log in to the CLI */
    data object AuthenticationRequired : ProbeError() {
        override val message: String get() = "Authentication required"
    }

    /** The CLI output could not be parsed */
    data class ParseFailed(val reason: String) : ProbeError() {
        override val message: String get() = "Failed to parse output: $reason"
    }

    /** The probe timed out waiting for a response */
    data object Timeout : ProbeError() {
        override val message: String get() = "Probe timed out"
    }

    /** No quota data was available */
    data object NoData : ProbeError() {
        override val message: String get() = "No quota data available"
    }

    /** The CLI needs to be updated */
    data object UpdateRequired : ProbeError() {
        override val message: String get() = "CLI update required"
    }

    /** User needs to trust the current folder */
    data object FolderTrustRequired : ProbeError() {
        override val message: String get() = "Folder trust required"
    }

    /** Command execution failed */
    data class ExecutionFailed(val reason: String) : ProbeError() {
        override val message: String get() = "Execution failed: $reason"
    }
}
