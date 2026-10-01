import Foundation
import Domain

/// Default implementation of CodexRPCClient that communicates with `codex app-server`.
/// Uses RPCTransport for communication, enabling testability.
public final class DefaultCodexRPCClient: CodexRPCClient, @unchecked Sendable {
    private let executable: String
    private let cliExecutor: CLIExecutor
    private let transport: RPCTransport?
    private var nextID = 1

    /// Package-internal: allows tests to inject a mock transport for the production (no-injection) code path.
    var transportFactory: ((String, [String]) throws -> RPCTransport)?

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

    /// Arguments every Codex invocation gets, for both the app-server and the
    /// TTY fallback.
    ///
    /// `--ask-for-approval` must stay a value the CLI still knows: Codex dropped
    /// `untrusted` (leaving `on-request` and `never`), and an unknown value makes
    /// the CLI exit at argument parsing — which took out the RPC path *and* the
    /// TTY fallback at once (#259). `never` is accepted by old and new builds
    /// alike, and cannot stall a non-interactive pipe on an approval prompt.
    /// The read-only sandbox still keeps anything Codex might run boxed in.
    static let baseArguments = ["-s", "read-only", "-a", "never"]

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
        let ownsTransport: Bool
        if let transport = self.transport {
            activeTransport = transport
            ownsTransport = false
        } else {
            let factory = transportFactory ?? { exec, args in
                try ProcessRPCTransport(executable: exec, arguments: args)
            }
            activeTransport = try factory(executable, Self.baseArguments + ["app-server"])
            ownsTransport = true
        }
        defer {
            if ownsTransport {
                activeTransport.close()
            }
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
        let additional = parseAdditionalLimits(result["rateLimitsByLimitId"])

        // If plan is free and no limits, create default "unlimited" quotas
        if primary == nil && secondary == nil && additional.isEmpty {
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

        return CodexRateLimitsResponse(primary: primary, secondary: secondary, planType: planType, additional: additional)
    }

    // MARK: - TTY Fallback

    private func fetchViaTTY() async throws -> CodexRateLimitsResponse {
        AppLog.probes.info("Starting Codex TTY fallback...")

        let result = try await cliExecutor.execute(
            binary: executable,
            args: Self.baseArguments,
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

    /// The `rateLimitsByLimitId` key that mirrors the top-level `rateLimits`
    /// payload; every other key is an extra bucket (e.g. Codex Spark).
    static let mainLimitId = "codex"

    /// Parses the multi-bucket `rateLimitsByLimitId` map, skipping the main
    /// `codex` bucket (already surfaced via `rateLimits`) and any entry whose
    /// windows cannot be parsed.
    internal func parseAdditionalLimits(_ value: Any?) -> [CodexAdditionalLimit] {
        guard let map = value as? [String: Any] else { return [] }

        var limits: [CodexAdditionalLimit] = []
        for key in map.keys.sorted() {
            guard key != Self.mainLimitId, let entry = map[key] as? [String: Any] else { continue }

            let name = (entry["limitName"] as? String)
                ?? (entry["limitId"] as? String)
                ?? key
            let primary = parseWindow(entry["primary"])
            let secondary = parseWindow(entry["secondary"])
            guard primary != nil || secondary != nil else { continue }

            limits.append(CodexAdditionalLimit(name: name, primary: primary, secondary: secondary))
        }
        return limits
    }

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

        var resetsAt: Date?
        var resetDescription: String?
        if let seconds = dict["resetsAt"] as? Int {
            let date = Date(timeIntervalSince1970: TimeInterval(seconds))
            resetsAt = date
            resetDescription = formatResetTime(date)
        }

        let windowDuration = (dict["windowDurationMins"] as? Int).map { TimeInterval($0) * 60 }

        return CodexRateLimitWindow(
            usedPercent: usedPercent,
            resetDescription: resetDescription,
            resetsAt: resetsAt,
            windowDuration: windowDuration
        )
    }

    internal func formatResetTime(_ date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        if interval <= 0 { return "Resets soon" }

        let days = Int(interval / 86400)
        let hours = Int((interval.truncatingRemainder(dividingBy: 86400)) / 3600)
        let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)

        if days > 0 {
            return "Resets in \(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
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
