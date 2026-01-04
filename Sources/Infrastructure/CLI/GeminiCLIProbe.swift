import Foundation
import Domain

internal struct GeminiCLIProbe {
    private let timeout: TimeInterval
    private let cliExecutor: CLIExecutor

    init(timeout: TimeInterval, cliExecutor: CLIExecutor = DefaultCLIExecutor()) {
        self.timeout = timeout
        self.cliExecutor = cliExecutor
    }

    func probe() async throws -> UsageSnapshot {
        guard cliExecutor.locate("gemini") != nil else {
            // Log diagnostic info when binary not found
            let env = ProcessInfo.processInfo.environment
            AppLog.probes.error("Gemini binary 'gemini' not found in PATH")
            AppLog.probes.info("Current directory: \(FileManager.default.currentDirectoryPath)")
            AppLog.probes.info("PATH: \(env["PATH"] ?? "<not set>")")
            throw ProbeError.cliNotFound("gemini")
        }

        AppLog.probes.info("Starting Gemini CLI fallback...")

        let result: CLIResult
        do {
            result = try cliExecutor.execute(
                binary: "gemini",
                args: [],
                input: "/stats\n",
                timeout: timeout,
                workingDirectory: nil,
                autoResponses: [:]
            )
        } catch {
            AppLog.probes.error("Gemini CLI failed: \(error.localizedDescription)")
            throw mapError(error)
        }

        AppLog.probes.debug("Gemini CLI raw output:\n\(result.output)")

        let snapshot = try Self.parse(result.output)
        AppLog.probes.info("Gemini CLI probe success: \(snapshot.quotas.count) quotas found")
        return snapshot
    }

    // MARK: - CLI Parsing

    static func parse(_ text: String) throws -> UsageSnapshot {
        let clean = stripANSICodes(text)

        // Check for login errors
        let lower = clean.lowercased()
        if lower.contains("login with google") || lower.contains("use gemini api key") ||
           lower.contains("waiting for auth") {
            throw ProbeError.authenticationRequired
        }

        // Parse model usage table
        let quotas = parseModelUsageTable(clean)

        guard !quotas.isEmpty else {
            throw ProbeError.parseFailed("No usage data found in output")
        }

        return UsageSnapshot(
            providerId: "gemini",
            quotas: quotas,
            capturedAt: Date()
        )
    }

    // MARK: - Text Parsing Helpers

    private static func stripANSICodes(_ text: String) -> String {
        let pattern = #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"#
        return text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }

    private static func parseModelUsageTable(_ text: String) -> [UsageQuota] {
        let lines = text.components(separatedBy: .newlines)
        var quotas: [UsageQuota] = []

        // Pattern matches: "gemini-2.5-pro   -   100.0% (Resets in 24h)"
        let pattern = #"(gemini[-\w.]+)\s+.*?([0-9]+(?:\.[0-9]+)?)\s*%\s*\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        for line in lines {
            let cleanLine = line.replacingOccurrences(of: "│", with: " ")
            let range = NSRange(cleanLine.startIndex..<cleanLine.endIndex, in: cleanLine)
            guard let match = regex.firstMatch(in: cleanLine, options: [], range: range),
                  match.numberOfRanges >= 4 else { continue }

            guard let modelRange = Range(match.range(at: 1), in: cleanLine),
                  let pctRange = Range(match.range(at: 2), in: cleanLine),
                  let pct = Double(cleanLine[pctRange])
            else { continue }

            let modelId = String(cleanLine[modelRange])

            var resetText: String?
            if let resetRange = Range(match.range(at: 3), in: cleanLine) {
                resetText = String(cleanLine[resetRange]).trimmingCharacters(in: .whitespaces)
            }

            quotas.append(UsageQuota(
                percentRemaining: pct,
                quotaType: .modelSpecific(modelId),
                providerId: "gemini",
                resetText: resetText
            ))
        }

        return quotas
    }

    private func mapError(_ error: Error) -> ProbeError {
        if let runError = error as? InteractiveRunner.RunError {
            switch runError {
            case .binaryNotFound(let bin):
                return .cliNotFound(bin)
            case .timedOut:
                return .timeout
            case .launchFailed(let msg):
                return .executionFailed(msg)
            }
        }
        return .executionFailed(error.localizedDescription)
    }
}
