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

/// Response from Codex rate limits API.
public struct CodexRateLimitsResponse: Sendable, Equatable {
    public let primary: CodexRateLimitWindow?
    public let secondary: CodexRateLimitWindow?
    public let planType: String?

    public init(primary: CodexRateLimitWindow?, secondary: CodexRateLimitWindow?, planType: String? = nil) {
        self.primary = primary
        self.secondary = secondary
        self.planType = planType
    }
}

/// A rate limit window from Codex API.
public struct CodexRateLimitWindow: Sendable, Equatable {
    public let usedPercent: Double
    public let resetDescription: String?

    public init(usedPercent: Double, resetDescription: String?) {
        self.usedPercent = usedPercent
        self.resetDescription = resetDescription
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
                resetText: primary.resetDescription
            ))
        }

        if let secondary = limits.secondary {
            quotas.append(UsageQuota(
                percentRemaining: max(0, 100 - secondary.usedPercent),
                quotaType: .weekly,
                providerId: "codex",
                resetText: secondary.resetDescription
            ))
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

