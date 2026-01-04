import Foundation
import Domain

/// Default implementation of CodexRPCClient that communicates with `codex app-server`.
/// Uses RPCTransport for communication, enabling testability.
public final class DefaultCodexRPCClient: CodexRPCClient, @unchecked Sendable {
    private let executable: String
    private let cliExecutor: CLIExecutor
    private let transport: RPCTransport?
    private var nextID = 1

    /// Default initializer - uses real CLI executor and creates transport lazily.
    public init(executable: String = "codex", cliExecutor: CLIExecutor? = nil) {
        self.executable = executable
        self.cliExecutor = cliExecutor ?? DefaultCLIExecutor()
        self.transport = nil
    }

    /// Internal initializer for testing with mock transport.
    init(transport: RPCTransport, cliExecutor: CLIExecutor? = nil) {
        self.executable = "codex"
        self.cliExecutor = cliExecutor ?? DefaultCLIExecutor()
        self.transport = transport
    }

    public func isAvailable() -> Bool {
        let binaryName = executable
        if cliExecutor.locate(binaryName) != nil {
            return true
        }
        
        // Log diagnostic info when binary not found
        let env = ProcessInfo.processInfo.environment
        AppLog.probes.error("Codex binary '\(binaryName)' not found in PATH")
        AppLog.probes.info("Current directory: \(FileManager.default.currentDirectoryPath)")
        AppLog.probes.info("PATH: \(env["PATH"] ?? "<not set>")")
        return false
    }

    public func fetchRateLimits() async throws -> CodexRateLimitsResponse {
        // Try RPC first, fall back to TTY
        do {
            return try await fetchViaRPC()
        } catch {
            AppLog.probes.warning("Codex RPC failed: \(error.localizedDescription), trying TTY fallback...")
            return try await fetchViaTTY()
        }
    }

    // MARK: - RPC Approach

    private func fetchViaRPC() async throws -> CodexRateLimitsResponse {
        let activeTransport: RPCTransport
        if let transport = self.transport {
            activeTransport = transport
        } else {
            activeTransport = try ProcessRPCTransport(
                executable: executable,
                arguments: ["-s", "read-only", "-a", "untrusted", "app-server"]
            )
        }

        // Initialize RPC connection
        _ = try await request(transport: activeTransport, method: "initialize", params: [
            "clientInfo": ["name": "claudebar", "version": "1.0.0"]
        ])
        try sendNotification(transport: activeTransport, method: "initialized")

        // Fetch rate limits
        let message = try await request(transport: activeTransport, method: "account/rateLimits/read")

        // Log raw response
        if let data = try? JSONSerialization.data(withJSONObject: message, options: .prettyPrinted),
           let jsonString = String(data: data, encoding: .utf8) {
            AppLog.probes.debug("Codex RPC raw response:\n\(jsonString)")
        }

        guard let result = message["result"] as? [String: Any] else {
            AppLog.probes.error("No result in response: \(String(describing: message))")
            throw ProbeError.parseFailed("Invalid rate limits response")
        }

        guard let rateLimits = result["rateLimits"] as? [String: Any] else {
            AppLog.probes.error("No rateLimits in result: \(String(describing: result))")
            throw ProbeError.parseFailed("No rateLimits in response")
        }

        let planType = rateLimits["planType"] as? String
        AppLog.probes.info("Codex plan type: \(planType ?? "unknown")")

        let primary = parseWindow(rateLimits["primary"])
        let secondary = parseWindow(rateLimits["secondary"])

        // If plan is free and no limits, create default "unlimited" quotas
        if primary == nil && secondary == nil {
            if planType == "free" {
                AppLog.probes.info("Codex free plan - returning unlimited quotas")
                return CodexRateLimitsResponse(
                    primary: CodexRateLimitWindow(usedPercent: 0, resetDescription: "Free plan"),
                    secondary: nil,
                    planType: planType
                )
            }
            // No rate limit data available yet
            throw ProbeError.parseFailed("No rate limits available yet - make some API calls first")
        }

        return CodexRateLimitsResponse(primary: primary, secondary: secondary, planType: planType)
    }

    // MARK: - TTY Fallback

    private func fetchViaTTY() async throws -> CodexRateLimitsResponse {
        AppLog.probes.info("Starting Codex TTY fallback...")

        let result = try cliExecutor.execute(
            binary: executable,
            args: ["-s", "read-only", "-a", "untrusted"],
            input: "/status\n",
            timeout: 20.0,
            workingDirectory: nil,
            autoResponses: [:]
        )

        AppLog.probes.debug("Codex TTY raw output:\n\(result.output)")

        do {
            return try parseTTYOutput(result.output)
        } catch {
            AppLog.probes.debug("Working directory: \(FileManager.default.currentDirectoryPath)")
            throw error
        }
    }

    private func parseTTYOutput(_ text: String) throws -> CodexRateLimitsResponse {
        let clean = CodexUsageProbe.stripANSICodes(text)

        // Check for errors
        if let error = CodexUsageProbe.extractUsageError(clean) {
            throw error
        }

        let fiveHourPct = extractTTYPercent(labelSubstring: "5h limit", text: clean)
        let weeklyPct = extractTTYPercent(labelSubstring: "Weekly limit", text: clean)

        var primary: CodexRateLimitWindow?
        var secondary: CodexRateLimitWindow?

        if let pct = fiveHourPct {
            // TTY shows "% left", convert to usedPercent
            primary = CodexRateLimitWindow(usedPercent: Double(100 - pct), resetDescription: nil)
        }

        if let pct = weeklyPct {
            secondary = CodexRateLimitWindow(usedPercent: Double(100 - pct), resetDescription: nil)
        }

        guard primary != nil || secondary != nil else {
            throw ProbeError.parseFailed("Could not find usage limits in Codex output")
        }

        return CodexRateLimitsResponse(primary: primary, secondary: secondary)
    }

    private func extractTTYPercent(labelSubstring: String, text: String) -> Int? {
        let lines = text.components(separatedBy: .newlines)
        let label = labelSubstring.lowercased()

        for (idx, line) in lines.enumerated() where line.lowercased().contains(label) {
            let window = lines.dropFirst(idx).prefix(12)
            for candidate in window {
                if let pct = ttyPercentFromLine(candidate) {
                    return pct
                }
            }
        }
        return nil
    }

    private func ttyPercentFromLine(_ line: String) -> Int? {
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

    // MARK: - Parsing Helpers

    internal func parseWindow(_ value: Any?) -> CodexRateLimitWindow? {
        guard let dict = value as? [String: Any] else {
            AppLog.probes.debug("parseWindow: value is not a dict: \(String(describing: value))")
            return nil
        }

        AppLog.probes.debug("parseWindow dict keys: \(dict.keys.joined(separator: ", "))")

        guard let usedPercent = dict["usedPercent"] as? Double else {
            AppLog.probes.debug("parseWindow: no usedPercent in dict")
            return nil
        }

        var resetDescription: String?
        if let resetsAt = dict["resetsAt"] as? Int {
            let date = Date(timeIntervalSince1970: TimeInterval(resetsAt))
            resetDescription = formatResetTime(date)
        }

        return CodexRateLimitWindow(usedPercent: usedPercent, resetDescription: resetDescription)
    }

    internal func formatResetTime(_ date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        if interval <= 0 { return "Resets soon" }

        let hours = Int(interval / 3600)
        let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)

        if hours > 0 {
            return "Resets in \(hours)h \(minutes)m"
        } else {
            return "Resets in \(minutes)m"
        }
    }

    public func shutdown() {
        transport?.close()
    }

    // MARK: - JSON-RPC

    private func request(transport: RPCTransport, method: String, params: [String: Any]? = nil) async throws -> [String: Any] {
        let id = nextID
        nextID += 1

        try sendRequest(transport: transport, id: id, method: method, params: params)

        while true {
            let message = try await readNextMessage(transport: transport)

            // Skip notifications
            if message["id"] == nil {
                continue
            }

            guard let messageID = message["id"] as? Int, messageID == id else {
                continue
            }

            if let error = message["error"] as? [String: Any],
               let errorMessage = error["message"] as? String {
                throw ProbeError.executionFailed("RPC error: \(errorMessage)")
            }

            return message
        }
    }

    private func sendNotification(transport: RPCTransport, method: String) throws {
        let payload: [String: Any] = ["method": method, "params": [:]]
        try sendPayload(transport: transport, payload: payload)
    }

    private func sendRequest(transport: RPCTransport, id: Int, method: String, params: [String: Any]?) throws {
        let payload: [String: Any] = [
            "id": id,
            "method": method,
            "params": params ?? [:]
        ]
        try sendPayload(transport: transport, payload: payload)
    }

    private func sendPayload(transport: RPCTransport, payload: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: payload)
        try transport.send(data)
    }

    private func readNextMessage(transport: RPCTransport) async throws -> [String: Any] {
        while true {
            let data = try await transport.receive()
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            return json
        }
    }
}
