import Foundation
import Domain

/// Infrastructure adapter that probes the Claude CLI to fetch usage quotas.
/// Implements the UsageProbePort from the domain layer.
public struct ClaudeUsageProbe: UsageProbePort {
    public let provider: AIProvider = .claude

    private let claudeBinary: String
    private let timeout: TimeInterval

    public init(claudeBinary: String = "claude", timeout: TimeInterval = 20.0) {
        self.claudeBinary = claudeBinary
        self.timeout = timeout
    }

    public func isAvailable() async -> Bool {
        PTYCommandRunner.which(claudeBinary) != nil
    }

    public func probe() async throws -> UsageSnapshot {
        let runner = PTYCommandRunner()
        let options = PTYCommandRunner.Options(
            timeout: timeout,
            workingDirectory: probeWorkingDirectory(),
            extraArgs: ["/usage", "--allowed-tools", ""],
            sendOnSubstrings: [
                "Do you trust the files in this folder?": "y\r",
                "Ready to code here?": "\r",
                "Press Enter to continue": "\r",
            ]
        )

        let result: PTYCommandRunner.Result
        do {
            result = try runner.run(binary: claudeBinary, send: "", options: options)
        } catch let error as PTYCommandRunner.RunError {
            throw mapRunError(error)
        }

        return try parseClaudeOutput(result.text)
    }

    // MARK: - Parsing

    /// Parses Claude CLI output into a UsageSnapshot
    public static func parse(_ text: String) throws -> UsageSnapshot {
        try ClaudeUsageProbe().parseClaudeOutput(text)
    }

    private func parseClaudeOutput(_ text: String) throws -> UsageSnapshot {
        let clean = stripANSICodes(text)

        // Check for errors first
        if let error = extractUsageError(clean) {
            throw error
        }

        // Extract percentages
        let sessionPct = extractPercent(labelSubstring: "Current session", text: clean)
        let weeklyPct = extractPercent(labelSubstring: "Current week (all models)", text: clean)
        let opusPct = extractPercent(labelSubstrings: [
            "Current week (Opus)",
            "Current week (Sonnet only)",
            "Current week (Sonnet)",
        ], text: clean)

        guard let sessionPct else {
            throw ProbeError.parseFailed("Could not find session usage")
        }

        // Extract reset times
        let sessionReset = extractReset(labelSubstring: "Current session", text: clean)
        let weeklyReset = extractReset(labelSubstring: "Current week", text: clean)

        // Extract account info
        let email = extractEmail(text: clean)
        let org = extractOrganization(text: clean)
        let loginMethod = extractLoginMethod(text: clean)

        // Build quotas
        var quotas: [UsageQuota] = []

        quotas.append(UsageQuota(
            percentRemaining: Double(sessionPct),
            quotaType: .session,
            provider: .claude,
            resetsAt: parseResetDate(sessionReset)
        ))

        if let weeklyPct {
            quotas.append(UsageQuota(
                percentRemaining: Double(weeklyPct),
                quotaType: .weekly,
                provider: .claude,
                resetsAt: parseResetDate(weeklyReset)
            ))
        }

        if let opusPct {
            quotas.append(UsageQuota(
                percentRemaining: Double(opusPct),
                quotaType: .modelSpecific("opus"),
                provider: .claude,
                resetsAt: parseResetDate(weeklyReset)
            ))
        }

        return UsageSnapshot(
            provider: .claude,
            quotas: quotas,
            capturedAt: Date(),
            accountEmail: email,
            accountOrganization: org,
            loginMethod: loginMethod
        )
    }

    // MARK: - Text Parsing Helpers

    private func stripANSICodes(_ text: String) -> String {
        let pattern = #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"#
        return text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }

    private func extractPercent(labelSubstring: String, text: String) -> Int? {
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

    private func extractPercent(labelSubstrings: [String], text: String) -> Int? {
        for label in labelSubstrings {
            if let value = extractPercent(labelSubstring: label, text: text) {
                return value
            }
        }
        return nil
    }

    private func percentFromLine(_ line: String) -> Int? {
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

    private func extractReset(labelSubstring: String, text: String) -> String? {
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

    private func extractEmail(text: String) -> String? {
        let pattern = #"(?i)(?:Account|Email):\s*([^\s@]+@[^\s@]+)"#
        return extractFirst(pattern: pattern, text: text)
    }

    private func extractOrganization(text: String) -> String? {
        let pattern = #"(?i)(?:Org|Organization):\s*(.+)"#
        return extractFirst(pattern: pattern, text: text)
    }

    private func extractLoginMethod(text: String) -> String? {
        let pattern = #"(?i)login\s+method:\s*(.+)"#
        return extractFirst(pattern: pattern, text: text)
    }

    private func extractFirst(pattern: String, text: String) -> String? {
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

    private func parseResetDate(_ text: String?) -> Date? {
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

    private func extractUsageError(_ text: String) -> ProbeError? {
        let lower = text.lowercased()

        if lower.contains("do you trust the files in this folder?"), !lower.contains("current session") {
            return .folderTrustRequired(extractFolderFromTrustPrompt(text) ?? "unknown")
        }

        if lower.contains("token_expired") || lower.contains("token has expired") {
            return .authenticationRequired
        }

        if lower.contains("authentication_error") {
            return .authenticationRequired
        }

        return nil
    }

    private func extractFolderFromTrustPrompt(_ text: String) -> String? {
        let pattern = #"Do you trust the files in this folder\?\s*(?:\r?\n)+\s*([^\r\n]+)"#
        return extractFirst(pattern: pattern, text: text)
    }

    // MARK: - Helpers

    private func probeWorkingDirectory() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        let dir = base
            .appendingPathComponent("ClaudeBar", isDirectory: true)
            .appendingPathComponent("Probe", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func mapRunError(_ error: PTYCommandRunner.RunError) -> ProbeError {
        switch error {
        case .binaryNotFound(let bin):
            .cliNotFound(bin)
        case .timedOut:
            .timeout
        case .launchFailed(let msg):
            .executionFailed(msg)
        }
    }
}
