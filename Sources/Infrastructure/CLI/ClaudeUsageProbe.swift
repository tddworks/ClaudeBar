import Foundation
import Domain

/// Infrastructure adapter that probes the Claude CLI to fetch usage quotas.
/// Implements the UsageProbe protocol from the domain layer.
public final class ClaudeUsageProbe: UsageProbe, @unchecked Sendable {
    private let claudeBinary: String
    private let timeout: TimeInterval
    private let cliExecutor: CLIExecutor

    public init(
        claudeBinary: String = "claude",
        timeout: TimeInterval = 20.0,
        cliExecutor: CLIExecutor? = nil
    ) {
        self.claudeBinary = claudeBinary
        self.timeout = timeout
        self.cliExecutor = cliExecutor ?? DefaultCLIExecutor()
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
        let workingDir = probeWorkingDirectory()
        AppLog.probes.info("Starting Claude probe with /usage command...")

        let usageResult: CLIResult
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
                ]
            )
        } catch {
            AppLog.probes.error("Claude /usage probe failed: \(error.localizedDescription)")
            AppLog.probes.debug("Working directory: \(workingDir.path)")
            throw ProbeError.executionFailed(error.localizedDescription)
        }

        AppLog.probes.info("Claude /usage output:\n\(usageResult.output)")

        let snapshot: UsageSnapshot
        do {
            snapshot = try parseClaudeOutput(usageResult.output)
        } catch {
            AppLog.probes.debug("Working directory: \(workingDir.path)")
            throw error
        }
        
        AppLog.probes.info("Claude probe success: accountType=\(snapshot.accountType?.rawValue ?? "unknown"), quotas=\(snapshot.quotas.count)")
        for quota in snapshot.quotas {
            AppLog.probes.info("  - \(quota.quotaType.displayName): \(Int(quota.percentRemaining))% remaining")
        }
        if let cost = snapshot.costUsage {
            AppLog.probes.info("  - Extra usage: \(cost.formattedCost) / \(cost.formattedBudget ?? "N/A")")
        }

        return snapshot
    }

    // MARK: - Parsing

    /// Parses Claude CLI /usage output into a UsageSnapshot (for testing)
    public static func parse(_ text: String) throws -> UsageSnapshot {
        let probe = ClaudeUsageProbe()
        return try probe.parseClaudeOutput(text)
    }

    private func parseClaudeOutput(_ text: String) throws -> UsageSnapshot {
        let clean = stripANSICodes(text)

        // Check for errors first
        if let error = extractUsageError(clean) {
            throw error
        }

        // Detect account type from header (e.g., "Opus 4.5 · Claude Max" or "Opus 4.5 · Claude Pro")
        let accountType = detectAccountType(clean)
        let email = extractEmail(text: clean)
        let organization = extractOrganization(text: clean)
        let loginMethod = extractLoginMethod(text: clean)

        // Extract percentages
        let sessionPct = extractPercent(labelSubstring: "Current session", text: clean)
        let weeklyPct = extractPercent(labelSubstring: "Current week (all models)", text: clean)
        let opusPct = extractPercent(labelSubstrings: [
            "Current week (Opus)",
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

        // Extract Extra usage for Pro accounts (if enabled)
        let extraUsage = extractExtraUsage(clean)

        return UsageSnapshot(
            providerId: "claude",
            quotas: quotas,
            capturedAt: Date(),
            accountEmail: email,
            accountOrganization: organization,
            loginMethod: loginMethod,
            accountType: accountType,
            costUsage: extraUsage
        )
    }

    // MARK: - Account Type Detection

    /// Detects the account type from the /usage header line.
    /// Format: "Opus 4.5 · Claude Max · email@example.com's Organization"
    /// or "Opus 4.5 · Claude Pro · email@example.com's Organization"
    internal func detectAccountType(_ text: String) -> ClaudeAccountType {
        let lower = text.lowercased()
        AppLog.probes.debug("Detecting account type from /usage output...")

        // Check for Claude Pro in header (e.g., "Opus 4.5 · Claude Pro")
        if lower.contains("· claude pro") || lower.contains("·claude pro") {
            AppLog.probes.info("Detected Claude Pro account from header")
            return .pro
        }

        // Check for Claude Max in header (e.g., "Opus 4.5 · Claude Max")
        if lower.contains("· claude max") || lower.contains("·claude max") {
            AppLog.probes.info("Detected Claude Max account from header")
            return .max
        }

        // Check for Claude API (unlikely in /usage, but check anyway)
        if lower.contains("· claude api") || lower.contains("·claude api") ||
           lower.contains("api account") {
            AppLog.probes.info("Detected Claude API account from header")
            return .api
        }

        // Fallback: Check for presence of quota data (subscription accounts have quotas)
        let hasSessionQuota = lower.contains("current session") && (lower.contains("% left") || lower.contains("% used"))
        if hasSessionQuota {
            AppLog.probes.info("Detected subscription account from quota data, defaulting to Max")
            return .max
        }

        // Default to Max if we can't determine
        AppLog.probes.warning("Could not determine account type, defaulting to Max")
        return .max
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

    internal func stripANSICodes(_ text: String) -> String {
        let pattern = #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"#
        return text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
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
        let oldPattern = #"(?i)(?:Org|Organization):\s*(.+)"#
        if let org = extractFirst(pattern: oldPattern, text: text) {
            return org
        }

        // Try header format: "Opus 4.5 · Claude Max · email@example.com's Organization"
        // or "Opus 4.5 · Claude Pro · Organization"
        let headerPattern = #"·\s*Claude\s+(?:Max|Pro)\s*·\s*(.+?)(?:\s*$|\n)"#
        if let match = extractFirst(pattern: headerPattern, text: text) {
            // Clean up the organization string
            return match.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    internal func extractLoginMethod(text: String) -> String? {
        let pattern = #"(?i)login\s+method:\s*(.+)"#
        return extractFirst(pattern: pattern, text: text)
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

        if lower.contains("do you trust the files in this folder?"), !lower.contains("current session") {
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
