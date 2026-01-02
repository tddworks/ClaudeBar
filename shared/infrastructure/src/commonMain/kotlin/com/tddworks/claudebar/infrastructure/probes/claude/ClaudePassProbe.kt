package com.tddworks.claudebar.infrastructure.probes.claude

import com.tddworks.claudebar.domain.model.ClaudePass
import com.tddworks.claudebar.domain.model.ProbeError
import com.tddworks.claudebar.infrastructure.cli.CLIExecutor
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

/**
 * Interface for reading from the system clipboard (for testability)
 */
interface ClipboardReader {
    fun readString(): String?
}

/**
 * Protocol for probing Claude guest passes.
 */
interface ClaudePassProbing {
    suspend fun isAvailable(): Boolean
    suspend fun probe(): ClaudePass
}

/**
 * Probes the Claude CLI to fetch guest pass information.
 * Executes `claude /passes` which copies the referral link to clipboard.
 */
class ClaudePassProbe(
    private val cliExecutor: CLIExecutor,
    private val clipboardReader: ClipboardReader,
    private val claudeBinary: String = "claude",
    private val timeout: Duration = 20.seconds
) : ClaudePassProbing {

    companion object {
        private val ANSI_PATTERN = Regex("""\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])""")
        private val PASSES_COUNT_PATTERN = Regex("""(\d+)\s*left""", RegexOption.IGNORE_CASE)
        private val REFERRAL_URL_PATTERN = Regex("""https://claude\.ai/referral/[A-Za-z0-9_-]+""")
    }

    override suspend fun isAvailable(): Boolean {
        return cliExecutor.locate(claudeBinary) != null
    }

    override suspend fun probe(): ClaudePass {
        val result = cliExecutor.execute(
            binary = claudeBinary,
            args = listOf("/passes", "--allowed-tools", ""),
            input = "",
            timeout = timeout,
            autoResponses = mapOf(
                "Esc to cancel" to "\r",
                "Ready to code here?" to "\r",
                "Press Enter to continue" to "\r",
                "ctrl+t to disable" to "\r"
            )
        )

        val clean = stripANSICodes(result.output)

        // Check if the command succeeded
        val cleanLower = clean.lowercase()
        if (!cleanLower.contains("copied to clipboard") && !cleanLower.contains("referral")) {
            throw ProbeError.ParseFailed("Command did not indicate success")
        }

        // Try to get URL from output first, then fall back to clipboard
        var referralURL = extractReferralURL(clean)

        // Fall back to reading from clipboard
        if (referralURL == null) {
            val clipboardContent = clipboardReader.readString()
            if (clipboardContent != null) {
                referralURL = extractReferralURL(clipboardContent)
            }
        }

        if (referralURL == null) {
            throw ProbeError.ParseFailed("Could not find referral URL")
        }

        // Try to extract pass count if available
        val passCount = extractPassesCount(clean)

        return ClaudePass(
            passesRemaining = passCount,
            referralURL = referralURL
        )
    }

    // MARK: - Parsing

    /**
     * Parses Claude CLI /passes output into a ClaudePass (for testing)
     */
    fun parse(text: String): ClaudePass {
        val clean = stripANSICodes(text)

        val referralURL = extractReferralURL(clean)
            ?: throw ProbeError.ParseFailed("Could not find referral URL in output")

        val passesCount = extractPassesCount(clean)

        return ClaudePass(
            passesRemaining = passesCount,
            referralURL = referralURL
        )
    }

    // MARK: - Parsing Helpers

    internal fun stripANSICodes(text: String): String {
        return text.replace(ANSI_PATTERN, "")
    }

    internal fun extractPassesCount(text: String): Int? {
        val match = PASSES_COUNT_PATTERN.find(text) ?: return null
        return match.groupValues.getOrNull(1)?.toIntOrNull()
    }

    internal fun extractReferralURL(text: String): String? {
        val match = REFERRAL_URL_PATTERN.find(text) ?: return null
        return match.value
    }
}
