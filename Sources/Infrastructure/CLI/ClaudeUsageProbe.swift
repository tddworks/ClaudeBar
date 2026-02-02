import Foundation
import Domain
import SwiftTerm

/// Infrastructure adapter that probes the Claude CLI to fetch usage quotas.
/// Implements the UsageProbe protocol from the domain layer.
public final class ClaudeUsageProbe: UsageProbe, @unchecked Sendable {
    private let claudeBinary: String
    private let timeout: TimeInterval
    private let cliExecutor: CLIExecutor
    private let terminalRenderer: TerminalRenderer

    public init(
        claudeBinary: String = "claude",
        timeout: TimeInterval = 20.0,
        cliExecutor: CLIExecutor? = nil
    ) {
        self.claudeBinary = claudeBinary
        self.timeout = timeout
        self.cliExecutor = cliExecutor ?? DefaultCLIExecutor()
        self.terminalRenderer = TerminalRenderer(cols: 160, rows: 50)
    }

    public func isAvailable() async -> Bool {
        if cliExecutor.locate(claudeBinary) != nil {
            return true
        }
        
        // Log diagnostic info when binary not found
        let env = ProcessInfo.processInfo.environment
        AppLog.probes.error("Claude binary '\(claudeBinary)' not found in PATH")
        AppLog.probes.debug("Current directory: \(FileManager.default.currentDirectoryPath)")
        AppLog.probes.debug("PATH: \(env["PATH"] ?? "<not set>")")
        if let configDir = env["CLAUDE_CONFIG_DIR"] {
            AppLog.probes.debug("CLAUDE_CONFIG_DIR: \(configDir)")
        }
        return false
    }

    public func probe() async throws -> UsageSnapshot {
        let probeStart = CFAbsoluteTimeGetCurrent()
        let workingDir = probeWorkingDirectory()
        AppLog.probes.info("Starting Claude probe with /usage command...")

        let usageResult: CLIResult
        let cliStart = CFAbsoluteTimeGetCurrent()
        do {
            usageResult = try cliExecutor.execute(
                binary: claudeBinary,
                args: ["/usage", "--allowed-tools", ""],
                input: "",
                timeout: timeout,
                workingDirectory: workingDir,
                autoResponses: [
                    "Esc to cancel": "\r",  // Trust prompt - press Enter to confirm
                    "Ready to code here?": "\r",
                    "Press Enter to continue": "\r",
                    "ctrl+t to disable": "\r",  // Onboarding complete
                    "Yes, I trust this folder": "\r",  // New trust prompt format
                ]
            )
        } catch {
            AppLog.probes.error("Claude /usage probe failed: \(error.localizedDescription)")
            AppLog.probes.debug("Working directory: \(workingDir.path)")
            throw ProbeError.executionFailed(error.localizedDescription)
        }
        let cliElapsed = CFAbsoluteTimeGetCurrent() - cliStart
        AppLog.probes.debug("Claude CLI execution took \(String(format: "%.3f", cliElapsed))s")

        AppLog.probes.info("Claude /usage output:\n\(usageResult.output)")

        let parseStart = CFAbsoluteTimeGetCurrent()
        let snapshot: UsageSnapshot
        do {
            snapshot = try parseClaudeOutput(usageResult.output)
        } catch ProbeError.folderTrustRequired {
            // Auto-response failed to dismiss trust prompt — write trust to ~/.claude.json and retry
            AppLog.probes.info("Writing trust for probe directory and retrying...")
            if writeClaudeTrust(for: workingDir) {
                return try await probe()
            }
            throw ProbeError.folderTrustRequired
        } catch ProbeError.subscriptionRequired {
            // API Usage Billing accounts don't support /usage, try /cost instead
            AppLog.probes.info("Account requires /cost command, falling back...")
            return try await probeCost(workingDir: workingDir)
        } catch {
            AppLog.probes.debug("Working directory: \(workingDir.path)")
            throw error
        }
        let parseElapsed = CFAbsoluteTimeGetCurrent() - parseStart
        AppLog.probes.debug("Claude parsing took \(String(format: "%.3f", parseElapsed))s")

        let totalElapsed = CFAbsoluteTimeGetCurrent() - probeStart
        AppLog.probes.info("Claude probe success: accountTier=\(snapshot.accountTier?.badgeText ?? "unknown"), quotas=\(snapshot.quotas.count) (total: \(String(format: "%.3f", totalElapsed))s)")
        for quota in snapshot.quotas {
            AppLog.probes.info("  - \(quota.quotaType.displayName): \(Int(quota.percentRemaining))% remaining")
        }
        if let cost = snapshot.costUsage {
            AppLog.probes.info("  - Extra usage: \(cost.formattedCost) / \(cost.formattedBudget ?? "N/A")")
        }

        return snapshot
    }

    /// Probes using /cost command for API Usage Billing accounts
    private func probeCost(workingDir: URL) async throws -> UsageSnapshot {
        AppLog.probes.info("Starting Claude probe with /cost command...")

        let costResult: CLIResult
        do {
            costResult = try cliExecutor.execute(
                binary: claudeBinary,
                args: ["/cost", "--allowed-tools", ""],
                input: "",
                timeout: timeout,
                workingDirectory: workingDir,
                autoResponses: [
                    "Esc to cancel": "\r",
                    "Ready to code here?": "\r",
                    "Press Enter to continue": "\r",
                    "ctrl+t to disable": "\r",
                    "Yes, I trust this folder": "\r",  // New trust prompt format
                ]
            )
        } catch {
            AppLog.probes.error("Claude /cost probe failed: \(error.localizedDescription)")
            throw ProbeError.executionFailed(error.localizedDescription)
        }

        AppLog.probes.info("Claude /cost output:\n\(costResult.output)")

        let snapshot = try parseCostOutput(costResult.output)

        AppLog.probes.info("Claude /cost probe success: cost=\(snapshot.costUsage?.formattedCost ?? "N/A")")

        return snapshot
    }

    // MARK: - Parsing

    /// Parses Claude CLI /usage output into a UsageSnapshot (for testing)
    public static func parse(_ text: String) throws -> UsageSnapshot {
        let probe = ClaudeUsageProbe()
        return try probe.parseClaudeOutput(text)
    }

    /// Parses Claude CLI /cost output into a UsageSnapshot (for testing)
    public static func parseCost(_ text: String) throws -> UsageSnapshot {
        let probe = ClaudeUsageProbe()
        return try probe.parseCostOutput(text)
    }

    /// Parses /cost command output for API Usage Billing accounts.
    /// Format:
    /// ```
    /// Total cost:            $0.55
    /// Total duration (API):  6m 19.7s
    /// Total duration (wall): 6h 33m 10.2s
    /// Total code changes:    0 lines added, 0 lines removed
    /// ```
    internal func parseCostOutput(_ text: String) throws -> UsageSnapshot {
        let clean = renderTerminalOutput(text)

        // Extract total cost: "$0.55" or "0.55"
        guard let cost = extractCostValue(clean) else {
            AppLog.probes.error("Claude /cost parse failed: could not find 'Total cost' in output")
            AppLog.probes.debug("Raw output: \(clean)")
            throw ProbeError.parseFailed("Could not find total cost")
        }

        // Extract API duration in seconds
        let apiDuration = extractApiDuration(clean)

        let costUsage = CostUsage(
            totalCost: cost,
            budget: nil,
            apiDuration: apiDuration,
            providerId: "claude",
            capturedAt: Date(),
            resetsAt: nil,
            resetText: nil
        )

        return UsageSnapshot(
            providerId: "claude",
            quotas: [],
            capturedAt: Date(),
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: nil,
            accountTier: .claudeApi,
            costUsage: costUsage
        )
    }

    /// Extracts the total cost value from /cost output
    /// Looks for "Total cost:" followed by a dollar amount
    internal func extractCostValue(_ text: String) -> Decimal? {
        // Pattern: "Total cost:" followed by optional whitespace and "$X.XX"
        let pattern = #"total\s+cost:\s*\$?([\d,]+\.?\d*)"#
        guard let match = extractFirst(pattern: pattern, text: text) else {
            return nil
        }
        let cleanValue = match.replacingOccurrences(of: ",", with: "")
        return Decimal(string: cleanValue)
    }

    /// Extracts the API duration in seconds from /cost output
    /// Looks for "Total duration (API):" followed by a time string like "6m 19.7s"
    internal func extractApiDuration(_ text: String) -> TimeInterval {
        // Find the API duration line
        let pattern = #"total\s+duration\s*\(api\):\s*(.+?)(?:\n|$)"#
        guard let durationStr = extractFirst(pattern: pattern, text: text) else {
            return 0
        }

        return parseDurationString(durationStr)
    }

    /// Parses a duration string like "6m 19.7s" or "2h 30m 15s" into seconds
    internal func parseDurationString(_ text: String) -> TimeInterval {
        var totalSeconds: TimeInterval = 0

        // Extract hours
        if let hourMatch = text.range(of: #"(\d+(?:\.\d+)?)\s*h"#, options: [.regularExpression, .caseInsensitive]) {
            let hourStr = String(text[hourMatch]).filter { $0.isNumber || $0 == "." }
            if let hours = Double(hourStr) {
                totalSeconds += hours * 3600
            }
        }

        // Extract minutes
        if let minMatch = text.range(of: #"(\d+(?:\.\d+)?)\s*m(?!s)"#, options: [.regularExpression, .caseInsensitive]) {
            let minStr = String(text[minMatch]).filter { $0.isNumber || $0 == "." }
            if let minutes = Double(minStr) {
                totalSeconds += minutes * 60
            }
        }

        // Extract seconds
        if let secMatch = text.range(of: #"(\d+(?:\.\d+)?)\s*s"#, options: [.regularExpression, .caseInsensitive]) {
            let secStr = String(text[secMatch]).filter { $0.isNumber || $0 == "." }
            if let seconds = Double(secStr) {
                totalSeconds += seconds
            }
        }

        return totalSeconds
    }

    private func parseClaudeOutput(_ text: String) throws -> UsageSnapshot {
        let clean = renderTerminalOutput(text)

        // Log both original and normalized output for debugging
        AppLog.probes.debug("Claude /usage raw output (\(text.count) chars):\n\(text)")
        AppLog.probes.debug("Claude /usage normalized output (\(clean.count) chars):\n\(clean)")

        // Check for errors first
        if let error = extractUsageError(clean) {
            throw error
        }

        // Detect account type from header (e.g., "Opus 4.5 · Claude Max" or "Opus 4.5 · Claude Pro")
        let accountType = detectAccountType(clean)
        let email = extractEmail(text: clean)
        let organization = extractOrganization(text: clean)
        let loginMethod = extractLoginMethod(text: clean)

        // API Usage Billing accounts don't have quota data - fall back to /cost
        if accountType == .claudeApi {
            AppLog.probes.info("Detected API Usage Billing account, falling back to /cost")
            throw ProbeError.subscriptionRequired
        }

        // Extract percentages
        let sessionPct = extractPercent(labelSubstring: "Current session", text: clean)
        let weeklyPct = extractPercent(labelSubstring: "Current week (all models)", text: clean)
        // Check for model-specific quota (Opus or Sonnet)
        let opusPct = extractPercent(labelSubstring: "Current week (Opus)", text: clean)
        let sonnetPct = extractPercent(labelSubstrings: [
            "Current week (Sonnet only)",
            "Current week (Sonnet)",
        ], text: clean)

        guard let sessionPct else {
            AppLog.probes.error("Claude parse failed: could not find 'Current session' percentage in output")
            AppLog.probes.debug("Raw output (original, \(text.count) chars): \(text.debugDescription)")
            AppLog.probes.debug("Raw output (cleaned, \(clean.count) chars): \(clean)")
            throw ProbeError.parseFailed("Could not find session usage")
        }

        // Extract reset times
        let sessionReset = extractReset(labelSubstring: "Current session", text: clean)
        let weeklyReset = extractReset(labelSubstring: "Current week", text: clean)

        // Build quotas
        var quotas: [UsageQuota] = []

        quotas.append(UsageQuota(
            percentRemaining: Double(sessionPct),
            quotaType: .session,
            providerId: "claude",
            resetsAt: parseResetDate(sessionReset),
            resetText: cleanResetText(sessionReset)
        ))

        if let weeklyPct {
            quotas.append(UsageQuota(
                percentRemaining: Double(weeklyPct),
                quotaType: .weekly,
                providerId: "claude",
                resetsAt: parseResetDate(weeklyReset),
                resetText: cleanResetText(weeklyReset)
            ))
        }

        if let opusPct {
            quotas.append(UsageQuota(
                percentRemaining: Double(opusPct),
                quotaType: .modelSpecific("opus"),
                providerId: "claude",
                resetsAt: parseResetDate(weeklyReset),
                resetText: cleanResetText(weeklyReset)
            ))
        }

        if let sonnetPct {
            quotas.append(UsageQuota(
                percentRemaining: Double(sonnetPct),
                quotaType: .modelSpecific("sonnet"),
                providerId: "claude",
                resetsAt: parseResetDate(weeklyReset),
                resetText: cleanResetText(weeklyReset)
            ))
        }

        // Extract Extra usage for Pro accounts (if enabled)
        let extraUsage = extractExtraUsage(clean)

        return UsageSnapshot(
            providerId: "claude",
            quotas: quotas,
            capturedAt: Date(),
            accountEmail: email,
            accountOrganization: organization,
            loginMethod: loginMethod,
            accountTier: accountType,
            costUsage: extraUsage
        )
    }

    // MARK: - Account Type Detection

    /// Detects the account tier from the /usage header line.
    /// Format: "Opus 4.5 · Claude Max · email@example.com's Organization"
    /// or "Opus 4.5 · Claude Pro · email@example.com's Organization"
    internal func detectAccountType(_ text: String) -> AccountTier {
        let lower = text.lowercased()
        AppLog.probes.debug("Detecting account tier from /usage output...")

        // Check for Claude Pro in header (e.g., "Opus 4.5 · Claude Pro")
        if lower.contains("· claude pro") || lower.contains("·claude pro") {
            AppLog.probes.info("Detected Claude Pro account from header")
            return .claudePro
        }

        // Check for Claude Max in header (e.g., "Opus 4.5 · Claude Max")
        if lower.contains("· claude max") || lower.contains("·claude max") {
            AppLog.probes.info("Detected Claude Max account from header")
            return .claudeMax
        }

        // Check for API Usage Billing in header (e.g., "Sonnet 4.5 · API Usage Billing")
        if lower.contains("api usage billing") {
            AppLog.probes.info("Detected API Usage Billing account from header")
            return .claudeApi
        }

        // Check for Claude API (unlikely in /usage, but check anyway)
        if lower.contains("· claude api") || lower.contains("·claude api") ||
           lower.contains("api account") {
            AppLog.probes.info("Detected Claude API account from header")
            return .claudeApi
        }

        // Fallback: Check for presence of quota data (subscription accounts have quotas)
        let hasSessionQuota = lower.contains("current session") && (lower.contains("% left") || lower.contains("% used"))
        if hasSessionQuota {
            AppLog.probes.info("Detected subscription account from quota data, defaulting to Max")
            return .claudeMax
        }

        // Default to Max if we can't determine
        AppLog.probes.warning("Could not determine account tier, defaulting to Max")
        return .claudeMax
    }

    // MARK: - Extra Usage Parsing

    /// Extracts Extra usage information from Pro accounts.
    /// Format: "Extra usage\n█████ 27% used\n$5.41 / $20.00 spent · Resets Jan 1, 2026"
    internal func extractExtraUsage(_ text: String) -> CostUsage? {
        let lines = text.components(separatedBy: .newlines)
        let lower = text.lowercased()

        // Check if Extra usage section exists
        guard lower.contains("extra usage") else {
            return nil
        }

        // Check if Extra usage is not enabled
        if lower.contains("extra usage not enabled") {
            AppLog.probes.debug("Extra usage not enabled for this account")
            return nil
        }

        // Find the Extra usage section
        var extraUsageIndex: Int?
        for (idx, line) in lines.enumerated() where line.lowercased().contains("extra usage") {
            extraUsageIndex = idx
            break
        }

        guard let startIndex = extraUsageIndex else {
            return nil
        }

        // Look for cost pattern in subsequent lines: "$5.41 / $20.00 spent"
        let window = lines.dropFirst(startIndex).prefix(10)
        for line in window {
            if let costInfo = parseExtraUsageCostLine(line) {
                let resetText = extractReset(labelSubstring: "Extra usage", text: text)
                let resetDate = parseResetDate(resetText)

                return CostUsage(
                    totalCost: costInfo.spent,
                    budget: costInfo.budget,
                    apiDuration: 0,
                    providerId: "claude",
                    capturedAt: Date(),
                    resetsAt: resetDate,
                    resetText: cleanResetText(resetText)
                )
            }
        }

        return nil
    }

    /// Parses a cost line like "$5.41 / $20.00 spent" and returns (spent, budget)
    internal func parseExtraUsageCostLine(_ line: String) -> (spent: Decimal, budget: Decimal)? {
        // Pattern: "$5.41 / $20.00 spent" or "5.41 / 20.00 spent"
        let pattern = #"\$?([\d,]+\.?\d*)\s*/\s*\$?([\d,]+\.?\d*)\s*spent"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              match.numberOfRanges >= 3,
              let spentRange = Range(match.range(at: 1), in: line),
              let budgetRange = Range(match.range(at: 2), in: line) else {
            return nil
        }

        let spentStr = String(line[spentRange]).replacingOccurrences(of: ",", with: "")
        let budgetStr = String(line[budgetRange]).replacingOccurrences(of: ",", with: "")

        guard let spent = Decimal(string: spentStr),
              let budget = Decimal(string: budgetStr) else {
            return nil
        }

        return (spent, budget)
    }

    // MARK: - Text Parsing Helpers

    /// Renders raw terminal output into clean text using SwiftTerm.
    /// Properly handles cursor movements, screen clearing, and other control sequences.
    internal func renderTerminalOutput(_ text: String) -> String {
        terminalRenderer.render(text)
    }

    internal func extractPercent(labelSubstring: String, text: String) -> Int? {
        let lines = text.components(separatedBy: .newlines)
        let label = labelSubstring.lowercased()

        for (idx, line) in lines.enumerated() where line.lowercased().contains(label) {
            let window = lines.dropFirst(idx).prefix(12)
            for candidate in window {
                if let pct = percentFromLine(candidate) {
                    return pct
                }
            }
        }
        return nil
    }

    internal func extractPercent(labelSubstrings: [String], text: String) -> Int? {
        for label in labelSubstrings {
            if let value = extractPercent(labelSubstring: label, text: text) {
                return value
            }
        }
        return nil
    }

    internal func percentFromLine(_ line: String) -> Int? {
        let pattern = #"([0-9]{1,3})\s*%\s*(used|left)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              match.numberOfRanges >= 3,
              let valRange = Range(match.range(at: 1), in: line),
              let kindRange = Range(match.range(at: 2), in: line) else {
            return nil
        }
        let rawVal = Int(line[valRange]) ?? 0
        let isUsed = line[kindRange].lowercased().contains("used")
        return isUsed ? max(0, 100 - rawVal) : rawVal
    }

    internal func extractReset(labelSubstring: String, text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        let label = labelSubstring.lowercased()

        for (idx, line) in lines.enumerated() where line.lowercased().contains(label) {
            let window = lines.dropFirst(idx).prefix(14)
            for candidate in window {
                let lower = candidate.lowercased()
                // Look for "resets" or time indicators like "2h" or "30m"
                if lower.contains("reset") ||
                   (lower.contains("in") && (lower.contains("h") || lower.contains("m"))) {
                    return candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return nil
    }

    internal func extractEmail(text: String) -> String? {
        // Try old format first: "Account: email" or "Email: email"
        let oldPattern = #"(?i)(?:Account|Email):\s*([^\s@]+@[^\s@]+)"#
        if let email = extractFirst(pattern: oldPattern, text: text) {
            return email
        }

        // Try header format: "Opus 4.5 · Claude Max · email@example.com's Organization"
        // Stop at apostrophe (') to not capture the "'s" part
        let headerPattern = #"·\s*Claude\s+(?:Max|Pro)\s*·\s*([^\s@]+@[^\s@']+)"#
        return extractFirst(pattern: headerPattern, text: text)
    }

    internal func extractOrganization(text: String) -> String? {
        // Try old format first: "Organization: org" or "Org: org"
        let oldPattern = #"(?i)(?:Org|Organization):\s*([^\n]+)"#
        if let org = extractFirst(pattern: oldPattern, text: text) {
            return org.trimmingCharacters(in: .whitespaces)
        }

        // Try header format: "Opus 4.5 · Claude Max · email@example.com's Organization"
        // or "Opus 4.5 · Claude Pro · Organization"
        let headerPattern = #"·\s*Claude\s+(?:Max|Pro)\s*·\s*([^\n]+)"#
        if let match = extractFirst(pattern: headerPattern, text: text) {
            return match.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    internal func extractLoginMethod(text: String) -> String? {
        let pattern = #"(?i)login\s+method:\s*([^\n]+)"#
        return extractFirst(pattern: pattern, text: text)?.trimmingCharacters(in: .whitespaces)
    }

    internal func extractFirst(pattern: String, text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 2,
              let r = Range(match.range(at: 1), in: text) else {
            return nil
        }
        // Terminal renderer pads lines with spaces - always trim the result
        return String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    internal func cleanResetText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // If it doesn't start with "Resets", add it
        if trimmed.lowercased().hasPrefix("reset") {
            return trimmed
        }
        return "Resets \(trimmed)"
    }

    internal func parseResetDate(_ text: String?) -> Date? {
        guard let text else { return nil }

        var totalSeconds: TimeInterval = 0

        // Extract days: "2d" or "2 d" or "2 days"
        if let dayMatch = text.range(of: #"(\d+)\s*d(?:ays?)?"#, options: .regularExpression) {
            let dayStr = String(text[dayMatch])
            if let days = Int(dayStr.filter { $0.isNumber }) {
                totalSeconds += Double(days) * 24 * 3600
            }
        }

        // Extract hours: "2h" or "2 h" or "2 hours"
        if let hourMatch = text.range(of: #"(\d+)\s*h(?:ours?|r)?"#, options: .regularExpression) {
            let hourStr = String(text[hourMatch])
            if let hours = Int(hourStr.filter { $0.isNumber }) {
                totalSeconds += Double(hours) * 3600
            }
        }

        // Extract minutes: "15m" or "15 m" or "15 min" or "15 minutes"
        if let minMatch = text.range(of: #"(\d+)\s*m(?:in(?:utes?)?)?"#, options: .regularExpression) {
            let minStr = String(text[minMatch])
            if let minutes = Int(minStr.filter { $0.isNumber }) {
                totalSeconds += Double(minutes) * 60
            }
        }

        if totalSeconds > 0 {
            return Date().addingTimeInterval(totalSeconds)
        }

        return nil
    }

    // MARK: - Error Detection

    internal func extractUsageError(_ text: String) -> ProbeError? {
        let lower = text.lowercased()

        if (lower.contains("do you trust the files in this folder?") ||
            lower.contains("is this a project you created or one you trust")),
           !lower.contains("current session") {
            AppLog.probes.error("Claude probe blocked: folder trust required")
            return .folderTrustRequired
        }

        if lower.contains("token_expired") || lower.contains("token has expired") {
            AppLog.probes.error("Claude probe failed: token has expired, re-authentication required")
            return .authenticationRequired
        }

        if lower.contains("authentication_error") {
            AppLog.probes.error("Claude probe failed: authentication error, login required")
            return .authenticationRequired
        }

        if lower.contains("not logged in") || lower.contains("please log in") {
            AppLog.probes.error("Claude probe failed: not logged in")
            return .authenticationRequired
        }

        if lower.contains("update required") || lower.contains("please update") {
            AppLog.probes.error("Claude probe failed: CLI update required")
            return .updateRequired
        }

        // Check for rate limit errors, but exclude promotional messages like "rate limits are 2x higher"
        let isRateLimitError = (lower.contains("rate limited") || 
                                lower.contains("rate limit exceeded") ||
                                lower.contains("too many requests")) &&
                               !lower.contains("rate limits are")
        if isRateLimitError {
            AppLog.probes.warning("Claude probe hit rate limit")
            return .executionFailed("Rate limited - too many requests")
        }

        return nil
    }

    internal func extractFolderFromTrustPrompt(_ text: String) -> String? {
        let pattern = #"Do you trust the files in this folder\?\s*(?:\r?\n)+\s*([^\r\n]+)"#
        return extractFirst(pattern: pattern, text: text)
    }

    // MARK: - Helpers

    /// Writes a trust entry for the given directory to ~/.claude.json so the CLI
    /// won't show the workspace trust dialog on next invocation.
    /// Returns true if the write succeeded.
    internal func writeClaudeTrust(for directory: URL) -> Bool {
        let configDir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
        let claudeJsonURL = (configDir ?? FileManager.default.homeDirectoryForCurrentUser)
            .appendingPathComponent(".claude.json")

        guard FileManager.default.fileExists(atPath: claudeJsonURL.path) else {
            AppLog.probes.warning("\(claudeJsonURL.path) not found, cannot write trust")
            return false
        }

        var root: [String: Any]
        if let data = try? Data(contentsOf: claudeJsonURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = json
        } else {
            AppLog.probes.warning("\(claudeJsonURL.path) is not valid JSON, cannot write trust")
            return false
        }

        if let existing = root["projects"], !(existing is [String: Any]) {
            AppLog.probes.warning("\(claudeJsonURL.path) 'projects' has unexpected type, refusing to overwrite")
            return false
        }
        var projects = root["projects"] as? [String: Any] ?? [:]
        let key = directory.path

        if let existingEntry = projects[key], !(existingEntry is [String: Any]) {
            AppLog.probes.warning("\(claudeJsonURL.path) project entry has unexpected type, refusing to overwrite")
            return false
        }
        var entry = projects[key] as? [String: Any] ?? [:]

        if entry["hasTrustDialogAccepted"] as? Bool == true {
            return false
        }

        entry["hasTrustDialogAccepted"] = true
        projects[key] = entry
        root["projects"] = projects

        do {
            let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: claudeJsonURL, options: .atomic)
            AppLog.probes.info("Wrote trust for \(key) to \(claudeJsonURL.path)")
            return true
        } catch {
            AppLog.probes.error("Failed to write trust to \(claudeJsonURL.path): \(error.localizedDescription)")
            return false
        }
    }

    internal func probeWorkingDirectory() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        let dir = base
            .appendingPathComponent("ClaudeBar", isDirectory: true)
            .appendingPathComponent("Probe", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
