import Foundation
import Domain
import Mockable

// MARK: - Codex Service Protocol

/// Protocol for Codex service - from user's mental model: "Is it available?" and "Get my stats"
@Mockable
public protocol CodexRPCClient: Sendable {
    /// Is the Codex CLI available on this system?
    func isAvailable() -> Bool
    /// Fetch rate limits from Codex service
    func fetchRateLimits() async throws -> CodexRateLimitsResponse
    /// Cleanup resources
    func shutdown()
}

/// A separate Codex rate-limit bucket alongside the main limits, e.g.
/// GPT-5.3-Codex-Spark's own 5h + weekly windows.
public struct CodexAdditionalLimit: Sendable, Equatable {
    /// Display name of the bucket (e.g. "Codex Spark"), taken from `limitName`
    /// and falling back to `limitId`.
    public let name: String
    public let primary: CodexRateLimitWindow?
    public let secondary: CodexRateLimitWindow?

    public init(name: String, primary: CodexRateLimitWindow? = nil, secondary: CodexRateLimitWindow? = nil) {
        self.name = name
        self.primary = primary
        self.secondary = secondary
    }
}

/// Response from Codex rate limits API.
public struct CodexRateLimitsResponse: Sendable, Equatable {
    public let primary: CodexRateLimitWindow?
    public let secondary: CodexRateLimitWindow?
    public let planType: String?
    /// Extra buckets beyond the main limits (e.g. Codex Spark), empty by
    /// default so existing callers keep their behavior.
    public let additional: [CodexAdditionalLimit]

    public init(
        primary: CodexRateLimitWindow?,
        secondary: CodexRateLimitWindow?,
        planType: String? = nil,
        additional: [CodexAdditionalLimit] = []
    ) {
        self.primary = primary
        self.secondary = secondary
        self.planType = planType
        self.additional = additional
    }
}

/// A rate limit window from Codex API.
public struct CodexRateLimitWindow: Sendable, Equatable {
    public let usedPercent: Double
    public let resetDescription: String?
    /// When the window resets. Kept alongside the text so the countdown can tick.
    public let resetsAt: Date?
    /// Length of the window, when Codex reports it (`windowDurationMins`).
    public let windowDuration: TimeInterval?

    public init(usedPercent: Double, resetDescription: String?, resetsAt: Date? = nil, windowDuration: TimeInterval? = nil) {
        self.usedPercent = usedPercent
        self.resetDescription = resetDescription
        self.resetsAt = resetsAt
        self.windowDuration = windowDuration
    }
}

/// Infrastructure adapter that probes the Codex CLI to fetch usage quotas.
public struct CodexUsageProbe: UsageProbe {
    private let client: CodexRPCClient

    public init(client: CodexRPCClient? = nil) {
        self.client = client ?? DefaultCodexRPCClient()
    }

    public func isAvailable() async -> Bool {
        client.isAvailable()
    }

    public func probe() async throws -> UsageSnapshot {
        AppLog.probes.info("Starting Codex probe...")
        defer { client.shutdown() }

        let limits = try await client.fetchRateLimits()
        let snapshot = try Self.mapRateLimitsToSnapshot(limits)

        AppLog.probes.info("Codex probe success: \(snapshot.quotas.count) quotas found")
        for quota in snapshot.quotas {
            AppLog.probes.info("  - \(quota.quotaType.displayName): \(Int(quota.percentRemaining))% remaining")
        }
        return snapshot
    }

    /// Maps RPC rate limits response to a UsageSnapshot (internal for testing).
    internal static func mapRateLimitsToSnapshot(_ limits: CodexRateLimitsResponse) throws -> UsageSnapshot {
        var quotas: [UsageQuota] = []

        if let primary = limits.primary {
            quotas.append(UsageQuota(
                percentRemaining: max(0, 100 - primary.usedPercent),
                quotaType: .session,
                providerId: "codex",
                resetsAt: primary.resetsAt,
                resetText: primary.resetDescription,
                windowDuration: primary.windowDuration
            ))
        }

        if let secondary = limits.secondary {
            quotas.append(UsageQuota(
                percentRemaining: max(0, 100 - secondary.usedPercent),
                quotaType: .weekly,
                providerId: "codex",
                resetsAt: secondary.resetsAt,
                resetText: secondary.resetDescription,
                windowDuration: secondary.windowDuration
            ))
        }

        for limit in limits.additional {
            let label = menuLabel(for: limit.name)
            guard !label.isEmpty else { continue }
            if let primary = limit.primary {
                quotas.append(UsageQuota(
                    percentRemaining: max(0, 100 - primary.usedPercent),
                    quotaType: .timeLimit(label),
                    providerId: "codex",
                    resetsAt: primary.resetsAt,
                    resetText: primary.resetDescription,
                    windowDuration: primary.windowDuration
                ))
            }
            if let secondary = limit.secondary {
                quotas.append(UsageQuota(
                    percentRemaining: max(0, 100 - secondary.usedPercent),
                    quotaType: .timeLimit(label + " 7d"),
                    providerId: "codex",
                    resetsAt: secondary.resetsAt,
                    resetText: secondary.resetDescription,
                    windowDuration: secondary.windowDuration
                ))
            }
        }

        guard !quotas.isEmpty else {
            AppLog.probes.error("Codex probe failed: no rate limits in RPC response")
            throw ProbeError.parseFailed("No rate limits found")
        }

        return UsageSnapshot(
            providerId: "codex",
            quotas: quotas,
            capturedAt: Date()
        )
    }

    /// Trims a limit id or name to the menu-friendly distinguishing part:
    /// "Codex Spark" and "codex_spark" both become "Spark"; anything without
    /// the redundant prefix is kept as-is.
    static func menuLabel(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()
        if lower.hasPrefix("codex_") {
            let rest = String(trimmed.dropFirst("codex_".count))
            guard !rest.isEmpty else { return trimmed }
            return rest.prefix(1).uppercased() + rest.dropFirst()
        }
        if lower.hasPrefix("codex ") {
            let rest = String(trimmed.dropFirst("codex ".count))
            return rest.isEmpty ? trimmed : rest
        }
        return trimmed
    }

    // MARK: - Parsing (for TTY fallback)

    public static func parse(_ text: String) throws -> UsageSnapshot {
        let clean = stripANSICodes(text)

        if let error = extractUsageError(clean) {
            throw error
        }

        let fiveHourPct = extractPercent(labelSubstring: "5h limit", text: clean)
        let weeklyPct = extractPercent(labelSubstring: "Weekly limit", text: clean)

        var quotas: [UsageQuota] = []

        if let fiveHourPct {
            quotas.append(UsageQuota(
                percentRemaining: Double(fiveHourPct),
                quotaType: .session,
                providerId: "codex"
            ))
        }

        if let weeklyPct {
            quotas.append(UsageQuota(
                percentRemaining: Double(weeklyPct),
                quotaType: .weekly,
                providerId: "codex"
            ))
        }

        if quotas.isEmpty {
            AppLog.probes.error("Codex parse failed: could not find usage limits in TTY output")
            AppLog.probes.debug("Raw output (original, \(text.count) chars): \(text.debugDescription)")
            AppLog.probes.debug("Raw output (cleaned, \(clean.count) chars): \(clean)")
            throw ProbeError.parseFailed("Could not find usage limits in Codex output")
        }

        return UsageSnapshot(
            providerId: "codex",
            quotas: quotas,
            capturedAt: Date()
        )
    }

    // MARK: - Text Parsing Helpers

    internal static func stripANSICodes(_ text: String) -> String {
        let pattern = #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"#
        return text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }

    private static func extractPercent(labelSubstring: String, text: String) -> Int? {
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

    private static func percentFromLine(_ line: String) -> Int? {
        let pattern = #"([0-9]{1,3})%\s+left"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              match.numberOfRanges >= 2,
              let valRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return Int(line[valRange])
    }

    internal static func extractUsageError(_ text: String) -> ProbeError? {
        let lower = text.lowercased()

        if lower.contains("data not available yet") {
            AppLog.probes.error("Codex probe failed: data not available yet")
            return .parseFailed("Data not available yet")
        }

        if lower.contains("update available") && lower.contains("codex") {
            AppLog.probes.error("Codex probe failed: CLI update required")
            return .updateRequired
        }

        if lower.contains("not logged in") || lower.contains("please log in") {
            AppLog.probes.error("Codex probe failed: not logged in")
            return .authenticationRequired
        }

        return nil
    }
}

