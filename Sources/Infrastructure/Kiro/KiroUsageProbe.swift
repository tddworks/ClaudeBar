import Foundation
import Domain

/// Infrastructure adapter that probes the Kiro CLI to fetch usage quotas.
/// Starts the interactive `kiro-cli` and sends `/usage` to parse the output.
///
/// Sample CLI output:
/// ```
/// Estimated Usage | resets on 03/01 | KIRO FREE
///
/// 🎁 Bonus credits: 122.54/500 credits used, expires in 29 days
///
/// Credits (0.00 of 50 covered in plan)
/// ████████████████████████████████████████████████████████████████████████████████ 0%
/// ```
public struct KiroUsageProbe: UsageProbe {
    private let kiroBinary: String
    private let timeout: TimeInterval
    private let cliExecutor: CLIExecutor

    public init(
        kiroBinary: String = "kiro-cli",
        timeout: TimeInterval = 30.0,
        cliExecutor: CLIExecutor? = nil
    ) {
        self.kiroBinary = kiroBinary
        self.timeout = timeout
        self.cliExecutor = cliExecutor ?? SimpleCLIExecutor()
    }

    public func isAvailable() async -> Bool {
        if cliExecutor.locate(kiroBinary) != nil {
            return true
        }
        AppLog.probes.error("Kiro binary '\(kiroBinary)' not found in PATH")
        return false
    }

    public func probe() async throws -> UsageSnapshot {
        guard cliExecutor.locate(kiroBinary) != nil else {
            throw ProbeError.cliNotFound(kiroBinary)
        }

        AppLog.probes.info("Starting Kiro CLI probe with /usage command...")

        let result: CLIResult
        do {
            result = try cliExecutor.execute(
                binary: kiroBinary,
                args: [],
                input: "/usage\n/quit\n",
                timeout: timeout,
                workingDirectory: nil,
                autoResponses: [:]
            )
        } catch {
            AppLog.probes.error("Kiro CLI probe failed: \(error.localizedDescription)")
            throw ProbeError.executionFailed(error.localizedDescription)
        }

        AppLog.probes.debug("Kiro CLI /usage output:\n\(result.output)")

        let snapshot = try Self.parse(result.output)

        AppLog.probes.info("Kiro CLI probe success: \(snapshot.quotas.count) quotas found")

        return snapshot
    }

    // MARK: - Static Parsing (for testability)

    /// Parses the Kiro CLI `/usage` output into a UsageSnapshot.
    public static func parse(_ text: String) throws -> UsageSnapshot {
        var quotas: [UsageQuota] = []
        
        // Strip ANSI escape codes
        let cleanText = text.replacingOccurrences(of: #"\u001B\[[0-9;]*[a-zA-Z]"#, with: "", options: .regularExpression)

        // Parse bonus credits: "🎁 Bonus credits: 143.31/500 credits used"
        if let bonusMatch = cleanText.range(of: #"Bonus credits:\s*([\d.]+)/([\d.]+)"#, options: .regularExpression) {
            let bonusLine = String(cleanText[bonusMatch])
            let pattern = #"([\d.]+)/([\d.]+)"#
            if let numMatch = bonusLine.range(of: pattern, options: .regularExpression) {
                let numStr = String(bonusLine[numMatch])
                let parts = numStr.split(separator: "/")
                if parts.count == 2, let used = Double(parts[0]), let total = Double(parts[1]), total > 0 {
                    let remaining = ((total - used) / total) * 100
                    
                    var resetsAt: Date?
                    var resetText: String?
                    if let expiryMatch = cleanText.range(of: #"expires in (\d+) days"#, options: .regularExpression) {
                        let expiryStr = String(cleanText[expiryMatch])
                        let days = Int(expiryStr.filter { $0.isNumber }) ?? 0
                        resetsAt = Date().addingTimeInterval(Double(days) * 24 * 3600)
                        resetText = "Expires in \(days) days"
                    }
                    
                    quotas.append(UsageQuota(
                        percentRemaining: max(0, remaining),
                        quotaType: .weekly,
                        providerId: "kiro",
                        resetsAt: resetsAt,
                        resetText: resetText
                    ))
                }
            }
        }

        // Parse regular credits: "Credits (0.00 of 50 covered in plan)"
        if let creditsMatch = cleanText.range(of: #"Credits \(([\d.]+) of ([\d.]+)"#, options: .regularExpression) {
            let creditsLine = String(cleanText[creditsMatch])
            let pattern = #"([\d.]+) of ([\d.]+)"#
            if let numMatch = creditsLine.range(of: pattern, options: .regularExpression) {
                let numStr = String(creditsLine[numMatch])
                let parts = numStr.components(separatedBy: " of ")
                if parts.count == 2, let used = Double(parts[0]), let total = Double(parts[1]), total > 0 {
                    let remaining = ((total - used) / total) * 100
                    
                    var resetsAt: Date?
                    var resetText: String?
                    if let resetMatch = cleanText.range(of: #"resets on (\d{2}/\d{2})"#, options: .regularExpression) {
                        let resetStr = String(cleanText[resetMatch]).replacingOccurrences(of: "resets on ", with: "")
                        resetText = "Resets on \(resetStr)"
                        
                        let components = resetStr.split(separator: "/").compactMap { Int($0) }
                        if components.count == 2 {
                            var dateComponents = Calendar.current.dateComponents([.year], from: Date())
                            dateComponents.month = components[0]
                            dateComponents.day = components[1]
                            if var date = Calendar.current.date(from: dateComponents), date < Date() {
                                // If date is in the past, assume next year
                                dateComponents.year = (dateComponents.year ?? 0) + 1
                            }
                            resetsAt = Calendar.current.date(from: dateComponents)
                        }
                    }
                    
                    quotas.append(UsageQuota(
                        percentRemaining: max(0, remaining),
                        quotaType: .timeLimit("Monthly"),
                        providerId: "kiro",
                        resetsAt: resetsAt,
                        resetText: resetText
                    ))
                }
            }
        }

        guard !quotas.isEmpty else {
            throw ProbeError.parseFailed("No quota data found in Kiro CLI output")
        }

        return UsageSnapshot(
            providerId: "kiro",
            quotas: quotas,
            capturedAt: Date()
        )
    }
}
