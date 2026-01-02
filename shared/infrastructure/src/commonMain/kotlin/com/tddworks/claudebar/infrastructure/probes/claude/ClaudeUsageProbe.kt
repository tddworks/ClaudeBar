package com.tddworks.claudebar.infrastructure.probes.claude

import com.tddworks.claudebar.domain.model.AccountTier
import com.tddworks.claudebar.domain.model.CostUsage
import com.tddworks.claudebar.domain.model.ProbeError
import com.tddworks.claudebar.domain.model.QuotaType
import com.tddworks.claudebar.domain.model.UsageQuota
import com.tddworks.claudebar.domain.model.UsageSnapshot
import com.tddworks.claudebar.domain.provider.UsageProbe
import com.tddworks.claudebar.infrastructure.cli.CLIExecutor
import kotlinx.datetime.Clock
import kotlinx.datetime.DateTimeUnit
import kotlinx.datetime.Instant
import kotlinx.datetime.TimeZone
import kotlinx.datetime.plus
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

/**
 * Infrastructure adapter that probes the Claude CLI to fetch usage quotas.
 */
class ClaudeUsageProbe(
    private val cliExecutor: CLIExecutor,
    private val claudeBinary: String = "claude",
    private val timeout: Duration = 20.seconds
) : UsageProbe {

    companion object {
        private val ANSI_PATTERN = Regex("""\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])""")
    }

    override suspend fun isAvailable(): Boolean {
        return cliExecutor.locate(claudeBinary) != null
    }

    override suspend fun probe(): UsageSnapshot {
        val result = cliExecutor.execute(
            binary = claudeBinary,
            args = listOf("/usage", "--allowed-tools", ""),
            input = "",
            timeout = timeout,
            autoResponses = mapOf(
                "Esc to cancel" to "\r",
                "Ready to code here?" to "\r",
                "Press Enter to continue" to "\r",
                "ctrl+t to disable" to "\r"
            )
        )

        if (result.exitCode != 0 && result.output.isBlank()) {
            throw ProbeError.ExecutionFailed("Claude CLI failed with exit code ${result.exitCode}")
        }

        return parseClaudeOutput(result.output)
    }

    internal fun parseClaudeOutput(text: String): UsageSnapshot {
        val clean = stripANSICodes(text)

        // Check for errors first
        extractUsageError(clean)?.let { throw it }

        // Detect account type
        val accountTier = detectAccountType(clean)
        val email = extractEmail(clean)
        val organization = extractOrganization(clean)
        val loginMethod = extractLoginMethod(clean)

        // Extract percentages
        val sessionPct = extractPercent("Current session", clean)
        val weeklyPct = extractPercent("Current week (all models)", clean)
        val opusPct = extractPercent(
            listOf("Current week (Opus)", "Current week (Sonnet only)", "Current week (Sonnet)"),
            clean
        )

        if (sessionPct == null) {
            throw ProbeError.ParseFailed("Could not find session usage")
        }

        // Extract reset times
        val sessionReset = extractReset("Current session", clean)
        val weeklyReset = extractReset("Current week", clean)

        // Build quotas
        val quotas = mutableListOf<UsageQuota>()

        quotas.add(
            UsageQuota(
                percentRemaining = sessionPct.toDouble(),
                quotaType = QuotaType.Session,
                providerId = "claude",
                resetsAt = parseResetDate(sessionReset),
                resetText = cleanResetText(sessionReset)
            )
        )

        if (weeklyPct != null) {
            quotas.add(
                UsageQuota(
                    percentRemaining = weeklyPct.toDouble(),
                    quotaType = QuotaType.Weekly,
                    providerId = "claude",
                    resetsAt = parseResetDate(weeklyReset),
                    resetText = cleanResetText(weeklyReset)
                )
            )
        }

        if (opusPct != null) {
            quotas.add(
                UsageQuota(
                    percentRemaining = opusPct.toDouble(),
                    quotaType = QuotaType.ModelSpecific("opus"),
                    providerId = "claude",
                    resetsAt = parseResetDate(weeklyReset),
                    resetText = cleanResetText(weeklyReset)
                )
            )
        }

        // Extract Extra usage for Pro accounts
        val extraUsage = extractExtraUsage(clean)

        return UsageSnapshot(
            providerId = "claude",
            quotas = quotas,
            capturedAt = Clock.System.now(),
            accountEmail = email,
            accountOrganization = organization,
            loginMethod = loginMethod,
            accountTier = accountTier,
            costUsage = extraUsage
        )
    }

    // MARK: - Account Type Detection

    internal fun detectAccountType(text: String): AccountTier {
        val lower = text.lowercase()

        if (lower.contains("· claude pro") || lower.contains("·claude pro")) {
            return AccountTier.ClaudePro
        }

        if (lower.contains("· claude max") || lower.contains("·claude max")) {
            return AccountTier.ClaudeMax
        }

        if (lower.contains("· claude api") || lower.contains("·claude api") ||
            lower.contains("api account")
        ) {
            return AccountTier.ClaudeApi
        }

        // Fallback: Check for presence of quota data
        val hasSessionQuota = lower.contains("current session") &&
            (lower.contains("% left") || lower.contains("% used"))
        if (hasSessionQuota) {
            return AccountTier.ClaudeMax
        }

        return AccountTier.ClaudeMax
    }

    // MARK: - Extra Usage Parsing

    internal fun extractExtraUsage(text: String): CostUsage? {
        val lower = text.lowercase()

        if (!lower.contains("extra usage")) {
            return null
        }

        if (lower.contains("extra usage not enabled")) {
            return null
        }

        val lines = text.lines()
        var startIndex = -1

        for ((idx, line) in lines.withIndex()) {
            if (line.lowercase().contains("extra usage")) {
                startIndex = idx
                break
            }
        }

        if (startIndex == -1) return null

        val window = lines.drop(startIndex).take(10)
        for (line in window) {
            val costInfo = parseExtraUsageCostLine(line)
            if (costInfo != null) {
                val resetText = extractReset("Extra usage", text)
                val resetDate = parseResetDate(resetText)

                return CostUsage(
                    totalCost = costInfo.first,
                    budget = costInfo.second,
                    apiDuration = Duration.ZERO,
                    providerId = "claude",
                    capturedAt = Clock.System.now(),
                    resetsAt = resetDate,
                    resetText = cleanResetText(resetText)
                )
            }
        }

        return null
    }

    internal fun parseExtraUsageCostLine(line: String): Pair<Double, Double>? {
        val pattern = Regex("""\$?([\d,]+\.?\d*)\s*/\s*\$?([\d,]+\.?\d*)\s*spent""", RegexOption.IGNORE_CASE)
        val match = pattern.find(line) ?: return null

        val spentStr = match.groupValues[1].replace(",", "")
        val budgetStr = match.groupValues[2].replace(",", "")

        val spent = spentStr.toDoubleOrNull() ?: return null
        val budget = budgetStr.toDoubleOrNull() ?: return null

        return Pair(spent, budget)
    }

    // MARK: - Text Parsing Helpers

    internal fun stripANSICodes(text: String): String {
        return text.replace(ANSI_PATTERN, "")
    }

    internal fun extractPercent(labelSubstring: String, text: String): Int? {
        return extractPercent(listOf(labelSubstring), text)
    }

    internal fun extractPercent(labelSubstrings: List<String>, text: String): Int? {
        val lines = text.lines()

        for (label in labelSubstrings) {
            val labelLower = label.lowercase()
            for ((idx, line) in lines.withIndex()) {
                if (line.lowercase().contains(labelLower)) {
                    val window = lines.drop(idx).take(12)
                    for (candidate in window) {
                        percentFromLine(candidate)?.let { return it }
                    }
                }
            }
        }
        return null
    }

    internal fun percentFromLine(line: String): Int? {
        val pattern = Regex("""([0-9]{1,3})\s*%\s*(used|left)""", RegexOption.IGNORE_CASE)
        val match = pattern.find(line) ?: return null

        val rawVal = match.groupValues[1].toIntOrNull() ?: 0
        val isUsed = match.groupValues[2].lowercase().contains("used")

        return if (isUsed) maxOf(0, 100 - rawVal) else rawVal
    }

    internal fun extractReset(labelSubstring: String, text: String): String? {
        val lines = text.lines()
        val label = labelSubstring.lowercase()

        for ((idx, line) in lines.withIndex()) {
            if (line.lowercase().contains(label)) {
                val window = lines.drop(idx).take(14)
                for (candidate in window) {
                    val lower = candidate.lowercase()
                    if (lower.contains("reset") ||
                        (lower.contains("in") && (lower.contains("h") || lower.contains("m")))
                    ) {
                        return candidate.trim()
                    }
                }
            }
        }
        return null
    }

    internal fun extractEmail(text: String): String? {
        // Try old format: "Account: email" or "Email: email"
        val oldPattern = Regex("""(?i)(?:Account|Email):\s*([^\s@]+@[^\s@]+)""")
        oldPattern.find(text)?.groupValues?.getOrNull(1)?.let { return it }

        // Try header format: "Opus 4.5 · Claude Max · email@example.com's Organization"
        val headerPattern = Regex("""·\s*Claude\s+(?:Max|Pro)\s*·\s*([^\s@]+@[^\s@']+)""")
        return headerPattern.find(text)?.groupValues?.getOrNull(1)
    }

    internal fun extractOrganization(text: String): String? {
        // Try old format: "Organization: org"
        val oldPattern = Regex("""(?i)(?:Org|Organization):\s*(.+)""")
        oldPattern.find(text)?.groupValues?.getOrNull(1)?.trim()?.let { return it }

        // Try header format
        val headerPattern = Regex("""·\s*Claude\s+(?:Max|Pro)\s*·\s*(.+?)(?:\s*$|\n)""")
        return headerPattern.find(text)?.groupValues?.getOrNull(1)?.trim()
    }

    internal fun extractLoginMethod(text: String): String? {
        val pattern = Regex("""(?i)login\s+method:\s*(.+)""")
        return pattern.find(text)?.groupValues?.getOrNull(1)?.trim()
    }

    internal fun cleanResetText(text: String?): String? {
        if (text == null) return null
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return null

        return if (trimmed.lowercase().startsWith("reset")) {
            trimmed
        } else {
            "Resets $trimmed"
        }
    }

    internal fun parseResetDate(text: String?): Instant? {
        if (text == null) return null

        var totalSeconds = 0L

        // Extract days
        val dayPattern = Regex("""(\d+)\s*d(?:ays?)?""")
        dayPattern.find(text)?.groupValues?.getOrNull(1)?.toIntOrNull()?.let { days ->
            totalSeconds += days * 24 * 3600
        }

        // Extract hours
        val hourPattern = Regex("""(\d+)\s*h(?:ours?|r)?""")
        hourPattern.find(text)?.groupValues?.getOrNull(1)?.toIntOrNull()?.let { hours ->
            totalSeconds += hours * 3600
        }

        // Extract minutes
        val minPattern = Regex("""(\d+)\s*m(?:in(?:utes?)?)?""")
        minPattern.find(text)?.groupValues?.getOrNull(1)?.toIntOrNull()?.let { minutes ->
            totalSeconds += minutes * 60
        }

        return if (totalSeconds > 0) {
            Clock.System.now().plus(totalSeconds, DateTimeUnit.SECOND, TimeZone.UTC)
        } else {
            null
        }
    }

    // MARK: - Error Detection

    internal fun extractUsageError(text: String): ProbeError? {
        val lower = text.lowercase()

        if (lower.contains("do you trust the files in this folder?") && !lower.contains("current session")) {
            return ProbeError.FolderTrustRequired
        }

        if (lower.contains("token_expired") || lower.contains("token has expired")) {
            return ProbeError.AuthenticationRequired
        }

        if (lower.contains("authentication_error")) {
            return ProbeError.AuthenticationRequired
        }

        if (lower.contains("not logged in") || lower.contains("please log in")) {
            return ProbeError.AuthenticationRequired
        }

        if (lower.contains("update required") || lower.contains("please update")) {
            return ProbeError.UpdateRequired
        }

        val isRateLimitError = (lower.contains("rate limited") ||
            lower.contains("rate limit exceeded") ||
            lower.contains("too many requests")) &&
            !lower.contains("rate limits are")
        if (isRateLimitError) {
            return ProbeError.ExecutionFailed("Rate limited - too many requests")
        }

        return null
    }
}
