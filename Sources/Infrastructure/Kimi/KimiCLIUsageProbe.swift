import Foundation
import Domain

/// Infrastructure adapter that probes the Kimi CLI to fetch usage quotas.
/// Starts the interactive `kimi` CLI, sends `/usage`, and parses the output.
///
/// Sample CLI output (kimi CLI < 0.36):
/// ```
/// ╭─────────────────────────────── API Usage ───────────────────────────────╮
/// │  Weekly limit  ━━━━━━━━━━━━━━━━━━━━  100% left  (resets in 6d 23h 22m)  │
/// │  5h limit      ━━━━━━━━━━━━━━━━━━━━  100% left  (resets in 4h 22m)      │
/// ╰─────────────────────────────────────────────────────────────────────────╯
/// ```
///
/// Sample CLI output (kimi CLI >= 0.36):
/// ```
///   ╭ Usage ───────────────────────────────────────────────────────────╮
///   │   Weekly limit  ██████████████████░░  90% used  resets in 35m    │
///   │   5h limit      ██░░░░░░░░░░░░░░░░░░  12% used  resets in 3h 35m │
///   ╰──────────────────────────────────────────────────────────────────╯
/// ```
public struct KimiCLIUsageProbe: UsageProbe {
    private let kimiBinary: String
    private let timeout: TimeInterval
    private let cliExecutor: CLIExecutor

    public init(
        kimiBinary: String = "kimi",
        timeout: TimeInterval = 15.0,
        cliExecutor: CLIExecutor? = nil
    ) {
        self.kimiBinary = kimiBinary
        self.timeout = timeout
        self.cliExecutor = cliExecutor ?? DefaultCLIExecutor()
    }

    public func isAvailable() async -> Bool {
        if cliExecutor.locate(kimiBinary) != nil {
            return true
        }
        AppLog.probes.error("Kimi binary '\(kimiBinary)' not found in PATH")
        return false
    }

    public func probe() async throws -> UsageSnapshot {
        guard cliExecutor.locate(kimiBinary) != nil else {
            throw ProbeError.cliNotFound(kimiBinary)
        }

        AppLog.probes.info("Starting Kimi CLI probe with /usage command...")

        let result: CLIResult
        do {
            result = try await cliExecutor.execute(
                binary: kimiBinary,
                args: [],
                input: nil,
                timeout: timeout,
                workingDirectory: nil,
                autoResponses: [
                    // kimi CLI < 0.36 shows a 💫 prompt when ready for input.
                    "💫": "/usage\r",
                    // kimi CLI >= 0.36 dropped the 💫 prompt; its status footer
                    // ("context: N% ...") signals the TUI is ready instead.
                    "context:": "/usage\r",
                ]
            )
        } catch {
            AppLog.probes.error("Kimi CLI probe failed: \(error.localizedDescription)")
            throw ProbeError.executionFailed(error.localizedDescription)
        }

        AppLog.probes.info("Kimi CLI /usage output:\n\(result.output)")

        let snapshot = try Self.parse(result.output)

        AppLog.probes.info("Kimi CLI probe success: \(snapshot.quotas.count) quotas found")
        for quota in snapshot.quotas {
            AppLog.probes.info("  - \(quota.quotaType.displayName): \(Int(quota.percentRemaining))% remaining")
        }

        return snapshot
    }

    // MARK: - Static Parsing (for testability)

    /// Parses the Kimi CLI `/usage` output into a UsageSnapshot.
    ///
    /// Looks for lines containing known quota labels ("Weekly limit", "5h limit").
    /// Two output formats are supported:
    /// - kimi CLI < 0.36: `N% left  (resets in ...)`
    /// - kimi CLI >= 0.36: `N% used  resets in ...` (remaining = 100 - used)
    ///
    /// Expected format per quota line (with or without progress bars):
    /// ```
    /// Weekly limit  ━━━━━━━━━━━━━━━━━━━━  100% left  (resets in 6d 23h 22m)
    /// Weekly limit  ██████████████████░░   90% used  resets in 35m
    /// ```
    public static func parse(_ text: String) throws -> UsageSnapshot {
        var quotas: [UsageQuota] = []

        for line in text.components(separatedBy: .newlines) {
            let lower = line.lowercased()

            // Determine quota type from known labels
            let quotaType: QuotaType
            if lower.contains("weekly") {
                quotaType = .weekly
            } else if lower.contains("5h") || lower.contains("hour") {
                quotaType = .session
            } else {
                continue
            }

            // The TUI redraws the panel on resize/refresh; keep the first occurrence.
            if quotas.contains(where: { $0.quotaType == quotaType }) { continue }

            // Extract percent and reset text from either output format.
            let percent: Double
            var resetRaw: String?
            if lower.contains("% left") {
                // kimi CLI < 0.36: "100% left  (resets in 6d 23h 22m)"
                guard let percentMatch = line.range(of: #"(\d+)%\s+left"#, options: .regularExpression),
                      let remaining = Double(line[percentMatch].prefix(while: { $0.isNumber })) else {
                    continue
                }
                percent = remaining
                if let resetMatch = lower.range(of: #"\(resets\s+in\s+(.+?)\)"#, options: .regularExpression) {
                    resetRaw = String(lower[resetMatch])
                        .replacingOccurrences(of: "(resets in ", with: "")
                        .replacingOccurrences(of: ")", with: "")
                        .trimmingCharacters(in: .whitespaces)
                }
            } else if lower.contains("% used") {
                // kimi CLI >= 0.36: "90% used  resets in 35m"
                guard let percentMatch = line.range(of: #"(\d+)\s*%\s*used"#, options: .regularExpression),
                      let used = Double(line[percentMatch].prefix(while: { $0.isNumber })) else {
                    continue
                }
                percent = max(0, 100 - used)
                if let resetMatch = lower.range(of: #"resets\s+in\s+[0-9dhms ]+"#, options: .regularExpression) {
                    resetRaw = String(lower[resetMatch])
                        .replacingOccurrences(of: #"^resets\s+in\s+"#, with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespaces)
                }
            } else {
                continue
            }

            var resetText: String?
            var resetsAt: Date?
            if let resetRaw, !resetRaw.isEmpty {
                resetText = "Resets in \(resetRaw)"
                resetsAt = parseResetDuration(resetRaw)
            }

            quotas.append(UsageQuota(
                percentRemaining: percent,
                quotaType: quotaType,
                providerId: "kimi",
                resetsAt: resetsAt,
                resetText: resetText
            ))
        }

        guard !quotas.isEmpty else {
            throw ProbeError.parseFailed("No quota data found in Kimi CLI output")
        }

        return UsageSnapshot(
            providerId: "kimi",
            quotas: quotas,
            capturedAt: Date()
        )
    }

    // MARK: - Private Helpers

    /// Parses a relative duration string like "6d 23h 22m" or "4h 22m" into a future Date.
    static func parseResetDuration(_ text: String) -> Date? {
        var totalSeconds: TimeInterval = 0

        // Extract days
        if let dayMatch = text.range(of: #"(\d+)\s*d"#, options: .regularExpression) {
            let dayStr = String(text[dayMatch])
            if let days = Int(dayStr.filter { $0.isNumber }) {
                totalSeconds += Double(days) * 24 * 3600
            }
        }

        // Extract hours
        if let hourMatch = text.range(of: #"(\d+)\s*h"#, options: .regularExpression) {
            let hourStr = String(text[hourMatch])
            if let hours = Int(hourStr.filter { $0.isNumber }) {
                totalSeconds += Double(hours) * 3600
            }
        }

        // Extract minutes
        if let minMatch = text.range(of: #"(\d+)\s*m"#, options: .regularExpression) {
            let minStr = String(text[minMatch])
            if let minutes = Int(minStr.filter { $0.isNumber }) {
                totalSeconds += Double(minutes) * 60
            }
        }

        // Extract seconds
        if let secMatch = text.range(of: #"(\d+)\s*s"#, options: .regularExpression) {
            let secStr = String(text[secMatch])
            if let seconds = Int(secStr.filter { $0.isNumber }) {
                totalSeconds += Double(seconds)
            }
        }

        guard totalSeconds > 0 else { return nil }
        return Date().addingTimeInterval(totalSeconds)
    }
}
