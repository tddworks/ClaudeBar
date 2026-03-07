import Foundation
import Domain

/// Probes the AmpCode CLI for usage quota information.
/// AmpCode (by Sourcegraph) exposes usage data via the `amp usage` command.
public struct AmpCodeUsageProbe: UsageProbe {

    private let cliExecutor: any CLIExecutor
    private let timeout: TimeInterval

    public init(
        cliExecutor: (any CLIExecutor)? = nil,
        timeout: TimeInterval = 8.0
    ) {
        self.cliExecutor = cliExecutor ?? DefaultCLIExecutor()
        self.timeout = timeout
    }

    // MARK: - Constants

    private static let emailRegex = try! NSRegularExpression(pattern: #"Signed in as\s+(\S+)\s+\("#)
    private static let creditLineRegex = try! NSRegularExpression(
        pattern: #"^(.+?):\s*\$([0-9]+(?:\.[0-9]+)?)\s*/\s*\$([0-9]+(?:\.[0-9]+)?)\s+remaining"#,
        options: .caseInsensitive
    )
    private static let balanceLineRegex = try! NSRegularExpression(
        pattern: #"^(.+?):\s*\$([0-9]+(?:\.[0-9]+)?)\s+remaining"#,
        options: .caseInsensitive
    )
    
    private static let labelMappings: [String: String] = [
        "amp free": "Free",
        "individual credits": "Individual",
    ]

    // MARK: - UsageProbe

    public func isAvailable() async -> Bool {
        cliExecutor.locate("amp") != nil
    }

    public func probe() async throws -> UsageSnapshot {
        AppLog.probes.info("Starting AmpCode probe...")

        // Step 1: Locate the amp binary
        guard let ampPath = cliExecutor.locate("amp") else {
            AppLog.probes.error("AmpCode probe failed: amp binary not found")
            throw ProbeError.cliNotFound("AmpCode")
        }

        // Step 2: Execute `amp usage --no-color`
        let result: CLIResult
        do {
            result = try cliExecutor.execute(
                binary: ampPath,
                args: ["usage", "--no-color"],
                input: nil,
                timeout: timeout,
                workingDirectory: nil,
                autoResponses: [:]
            )
        } catch {
            AppLog.probes.error("AmpCode probe failed: \(error.localizedDescription)")
            throw ProbeError.executionFailed("amp usage failed: \(error.localizedDescription)")
        }

        guard result.exitCode == 0 else {
            AppLog.probes.error("AmpCode probe failed: exit code \(result.exitCode)")
            throw ProbeError.executionFailed("amp usage exited with code \(result.exitCode)")
        }

        AppLog.probes.debug("AmpCode usage output:\n\(result.output)")


        // Step 3: Parse output
        let snapshot = try Self.parse(result.output)

        // Redact email for logs (e.g. "u***@example.com")
        let redactedEmail = snapshot.accountEmail.map { email -> String in
            let parts = email.split(separator: "@")
            guard parts.count == 2 else { return "***" }
            let name = parts[0]
            let domain = parts[1]
            return "\(name.prefix(1))***@\(domain)"
        } ?? "none"

        AppLog.probes.info("AmpCode probe success: \(snapshot.quotas.count) quotas found, email=\(redactedEmail)")
        for quota in snapshot.quotas {
            AppLog.probes.info("  - \(quota.quotaType.displayName): \(Int(quota.percentRemaining))% remaining")
        }

        return snapshot
    }

    // MARK: - Static Parsing (for testability)

    /// Parses `amp usage` CLI output into a UsageSnapshot.
    ///
    /// Expected format:
    /// ```
    /// Signed in as user@example.com (username)
    /// Amp Free: $17.59/$20 remaining (replenishes +$0.83/hour) [+100% bonus for 19 more days] - https://...
    /// Individual credits: $0 remaining - https://...
    /// ```
    static func parse(_ text: String) throws -> UsageSnapshot {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Extract email from "Signed in as <email> (<username>)"
        let email = extractEmail(from: lines)

        // Parse credit lines:
        // - "$remaining/$total remaining" → percentage-based quota
        // - "$remaining remaining" (no total) → balance-based quota with dollarRemaining
        let quotas = lines.compactMap { parseCreditLine($0) ?? parseBalanceLine($0) }

        guard !quotas.isEmpty else {
            AppLog.probes.error("AmpCode parse failed: no valid credit lines found")
            throw ProbeError.parseFailed("No valid credit lines found in amp usage output")
        }

        return UsageSnapshot(
            providerId: "ampcode",
            quotas: quotas,
            capturedAt: Date(),
            accountEmail: email,
            accountTier: nil
        )
    }

    // MARK: - Private Parsing Helpers

    private static func extractEmail(from lines: [String]) -> String? {
        for line in lines {
            // Pattern: "Signed in as <email> (<username>)"
            guard let match = emailRegex.firstMatch(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line)),
                  let emailRange = Range(match.range(at: 1), in: line) else {
                continue
            }
            return String(line[emailRange])
        }
        return nil
    }

    /// Parses a credit line with $remaining/$total format into a percentage-based UsageQuota.
    /// Returns nil for lines without a denominator.
    ///
    /// Format: "<Label>: $<remaining>/$<total> remaining ..."
    private static func parseCreditLine(_ line: String) -> UsageQuota? {
        // Match pattern: "<Label>: $<remaining>/$<total> remaining"
        guard let match = creditLineRegex.firstMatch(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line)),
              let labelRange = Range(match.range(at: 1), in: line),
              let remainingRange = Range(match.range(at: 2), in: line),
              let totalRange = Range(match.range(at: 3), in: line) else {
            return nil
        }

        let rawLabel = String(line[labelRange]).trimmingCharacters(in: .whitespaces)
        let label = labelMappings[rawLabel.lowercased()] ?? rawLabel
        guard let remaining = Double(line[remainingRange]),
              let total = Double(line[totalRange]),
              total > 0 else {
            return nil
        }

        let percentRemaining = (remaining / total) * 100.0
        // Round to 2 decimal places for clean display
        let rounded = (percentRemaining * 100).rounded() / 100

        let resetText = String(format: "$%.2f/$%.2f", remaining, total)

        return UsageQuota(
            percentRemaining: rounded,
            quotaType: .modelSpecific(label),
            providerId: "ampcode",
            resetText: resetText
        )
    }

    /// Parses a balance line with no total into a credit-based UsageQuota.
    /// Uses dollarRemaining to store the balance, percentRemaining is 100 (no cap).
    ///
    /// Format: "<Label>: $<remaining> remaining ..."
    private static func parseBalanceLine(_ line: String) -> UsageQuota? {
        // Skip lines that match the $remaining/$total pattern (handled by parseCreditLine)
        if creditLineRegex.firstMatch(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line)) != nil {
            return nil
        }

        guard let match = balanceLineRegex.firstMatch(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line)),
              let labelRange = Range(match.range(at: 1), in: line),
              let amountRange = Range(match.range(at: 2), in: line) else {
            return nil
        }

        let rawLabel = String(line[labelRange]).trimmingCharacters(in: .whitespaces)
        let label = labelMappings[rawLabel.lowercased()] ?? rawLabel
        guard let amount = Decimal(string: String(line[amountRange])) else {
            return nil
        }

        return UsageQuota(
            percentRemaining: 100,
            quotaType: .modelSpecific(label),
            providerId: "ampcode",
            dollarRemaining: amount
        )
    }
}
