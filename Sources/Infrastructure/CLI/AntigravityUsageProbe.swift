import Foundation
import Domain

/// Probes the local Antigravity language server for usage quota information.
/// Antigravity runs as a local process and exposes quota data via a local API.
public struct AntigravityUsageProbe: UsageProbe {

    private let cliExecutor: any CLIExecutor
    private let insecureSession: URLSession
    private let timeout: TimeInterval

    // Match both Intel and ARM binaries
    private static let processNames = ["language_server_macos", "language_server_macos_arm"]

    public init(
        cliExecutor: (any CLIExecutor)? = nil,
        timeout: TimeInterval = 8.0
    ) {
        self.cliExecutor = cliExecutor ?? DefaultCLIExecutor()
        self.timeout = timeout

        // Create a session that accepts self-signed certificates for localhost
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        self.insecureSession = URLSession(
            configuration: config,
            delegate: InsecureLocalhostDelegate(),
            delegateQueue: nil
        )
    }

    // MARK: - UsageProbe

    public func isAvailable() async -> Bool {
        do {
            let processInfo = try await detectProcess()
            AppLog.probes.debug("Antigravity process detected: PID=\(processInfo.pid)")
            return true
        } catch {
            AppLog.probes.debug("Antigravity not available: \(error.localizedDescription)")
            return false
        }
    }

    public func probe() async throws -> UsageSnapshot {
        AppLog.probes.info("Starting Antigravity probe...")

        // Step 1: Detect running Antigravity process
        let processInfo: ProcessInfo
        do {
            processInfo = try await detectProcess()
            AppLog.probes.debug("Antigravity process found: PID=\(processInfo.pid), port=\(processInfo.extensionPort ?? 0)")
        } catch {
            AppLog.probes.error("Antigravity probe failed: \(error.localizedDescription)")
            throw error
        }

        // Step 2: Find listening ports
        let ports: [Int]
        do {
            ports = try await discoverPorts(pid: processInfo.pid)
            AppLog.probes.debug("Antigravity listening ports: \(ports)")
        } catch {
            AppLog.probes.error("Antigravity port discovery failed: \(error.localizedDescription)")
            throw error
        }

        // Step 3: Find working port and fetch quota
        let data: Data
        do {
            data = try await fetchQuota(ports: ports, csrfToken: processInfo.csrfToken, httpPort: processInfo.extensionPort)
            AppLog.probes.debug("Antigravity API response received: \(data.count) bytes")
        } catch {
            AppLog.probes.error("Antigravity API request failed: \(error.localizedDescription)")
            throw error
        }

        // Log raw response at debug level
        if let responseText = String(data: data, encoding: .utf8) {
            AppLog.probes.debug("Antigravity API response: \(responseText.prefix(500))")
        }

        // Step 4: Parse response
        let snapshot = try Self.parseUserStatusResponse(data, providerId: "antigravity")

        AppLog.probes.info("Antigravity probe success: \(snapshot.quotas.count) quotas found, email=\(snapshot.accountEmail ?? "none")")
        for quota in snapshot.quotas {
            AppLog.probes.info("  - \(quota.quotaType.displayName): \(Int(quota.percentRemaining))% remaining")
        }

        return snapshot
    }

    // MARK: - Process Detection

    private struct ProcessInfo {
        let pid: Int
        let csrfToken: String
        let extensionPort: Int?
    }

    private func detectProcess() async throws -> ProcessInfo {
        // Use -ww for wide output to avoid command line truncation
        let result = try cliExecutor.execute(
            binary: "/bin/ps",
            args: ["-ax", "-ww", "-o", "pid=,command="],
            input: nil,
            timeout: timeout,
            workingDirectory: nil,
            autoResponses: [:]
        )

        // Handle different line endings from PTY output (\n, \r\n, \r)
        let normalizedOutput = result.output
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalizedOutput.split(separator: "\n", omittingEmptySubsequences: true)

        AppLog.probes.debug("Antigravity: ps returned \(lines.count) process lines")

        for line in lines {
            let lineStr = String(line).trimmingCharacters(in: .whitespaces)
            guard Self.isAntigravityProcess(lineStr) else { continue }

            guard let pid = Self.extractPID(from: lineStr) else { continue }

            // Debug: log the command line we're parsing
            AppLog.probes.debug("Antigravity: Checking process line (length=\(lineStr.count)): \(lineStr.prefix(200))...")

            if let csrfToken = Self.extractCSRFToken(from: lineStr) {
                let extensionPort = Self.extractExtensionPort(from: lineStr)
                AppLog.probes.debug("Antigravity process detected: PID=\(pid), hasCSRF=true, extPort=\(extensionPort ?? 0)")
                return ProcessInfo(pid: pid, csrfToken: csrfToken, extensionPort: extensionPort)
            } else {
                // Process found but no CSRF token - log more details
                AppLog.probes.error("Antigravity process found (PID=\(pid)) but missing CSRF token")
                AppLog.probes.debug("Antigravity: Full command line: \(lineStr)")
                AppLog.probes.debug("Antigravity: Contains --csrf_token? \(lineStr.contains("--csrf_token"))")
                throw ProbeError.authenticationRequired
            }
        }

        AppLog.probes.debug("Antigravity language server process not found")
        throw ProbeError.cliNotFound("Antigravity")
    }

    // MARK: - Port Discovery

    private func discoverPorts(pid: Int) async throws -> [Int] {
        let lsofPath = ["/usr/sbin/lsof", "/usr/bin/lsof"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        } ?? "/usr/sbin/lsof"

        let result = try cliExecutor.execute(
            binary: lsofPath,
            args: ["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p", String(pid)],
            input: nil,
            timeout: timeout,
            workingDirectory: nil,
            autoResponses: [:]
        )

        let ports = Self.parseListeningPorts(from: result.output)

        if ports.isEmpty {
            AppLog.probes.error("Antigravity: No listening ports found for PID \(pid)")
            AppLog.probes.debug("lsof output: \(result.output.prefix(500))")
            throw ProbeError.executionFailed("No listening ports found for Antigravity")
        }

        AppLog.probes.debug("Antigravity: Found \(ports.count) listening ports: \(ports)")
        return ports
    }

    // MARK: - API Calls

    private func fetchQuota(ports: [Int], csrfToken: String, httpPort: Int?) async throws -> Data {
        let paths = [
            "/exa.language_server_pb.LanguageServerService/GetUserStatus",
            "/exa.language_server_pb.LanguageServerService/GetCommandModelConfigs"
        ]

        // Try HTTPS ports first
        for port in ports {
            for path in paths {
                AppLog.probes.debug("Antigravity: Trying https://127.0.0.1:\(port)\(path)")
                if let data = try? await makeRequest(scheme: "https", port: port, path: path, csrfToken: csrfToken) {
                    AppLog.probes.debug("Antigravity: Success on port \(port)")
                    return data
                }
            }
        }

        // Fallback to HTTP on extension port
        if let httpPort {
            for path in paths {
                AppLog.probes.debug("Antigravity: Trying HTTP fallback on port \(httpPort)")
                if let data = try? await makeRequest(scheme: "http", port: httpPort, path: path, csrfToken: csrfToken) {
                    AppLog.probes.debug("Antigravity: Success on HTTP port \(httpPort)")
                    return data
                }
            }
        }

        AppLog.probes.error("Antigravity: Could not connect to API on any port")
        throw ProbeError.executionFailed("Could not connect to Antigravity API")
    }

    private func makeRequest(scheme: String, port: Int, path: String, csrfToken: String) async throws -> Data {
        guard let url = URL(string: "\(scheme)://127.0.0.1:\(port)\(path)") else {
            throw ProbeError.executionFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(csrfToken, forHTTPHeaderField: "X-Codeium-Csrf-Token")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")

        let body: [String: Any] = [
            "metadata": [
                "ideName": "antigravity",
                "extensionName": "antigravity",
                "ideVersion": "unknown",
                "locale": "en"
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        // Use insecure session for self-signed localhost certificates
        let (data, response) = try await insecureSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ProbeError.executionFailed("API request failed")
        }

        return data
    }

    // MARK: - Static Parsing Helpers (for testability)

    static func isAntigravityProcess(_ commandLine: String) -> Bool {
        let lower = commandLine.lowercased()
        // Check if any of the known process names are present
        guard processNames.contains(where: { lower.contains($0) }) else { return false }
        // Check for app_data_dir flag with antigravity value
        if lower.contains("--app_data_dir") && lower.contains("antigravity") {
            return true
        }
        // Check for antigravity in the path (e.g., ~/.antigravity/language_server_macos)
        if lower.contains("/antigravity/") || lower.contains(".antigravity/") {
            return true
        }
        return false
    }

    static func extractPID(from line: String) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = parts.first else { return nil }
        return Int(first)
    }

    static func extractCSRFToken(from commandLine: String) -> String? {
        extractFlag("--csrf_token", from: commandLine)
    }

    static func extractExtensionPort(from commandLine: String) -> Int? {
        guard let portStr = extractFlag("--extension_server_port", from: commandLine) else { return nil }
        return Int(portStr)
    }

    private static func extractFlag(_ flag: String, from command: String) -> String? {
        let pattern = "\(NSRegularExpression.escapedPattern(for: flag))[=\\s]+([^\\s]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(command.startIndex..<command.endIndex, in: command)
        guard let match = regex.firstMatch(in: command, options: [], range: range),
              let tokenRange = Range(match.range(at: 1), in: command) else { return nil }
        return String(command[tokenRange])
    }

    static func parseListeningPorts(from output: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: #":(\d+)\s+\(LISTEN\)"#) else { return [] }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        var ports: Set<Int> = []
        regex.enumerateMatches(in: output, options: [], range: range) { match, _, _ in
            guard let match,
                  let range = Range(match.range(at: 1), in: output),
                  let value = Int(output[range]) else { return }
            ports.insert(value)
        }
        return ports.sorted()
    }

    // MARK: - Response Parsing (Static for testability)

    /// Parses the UserStatus API response into a UsageSnapshot
    static func parseUserStatusResponse(_ data: Data, providerId: String) throws -> UsageSnapshot {
        let decoder = JSONDecoder()

        let response: UserStatusResponse
        do {
            response = try decoder.decode(UserStatusResponse.self, from: data)
        } catch {
            AppLog.probes.error("Antigravity parse failed: Invalid JSON - \(error.localizedDescription)")
            if let rawString = String(data: data, encoding: .utf8) {
                AppLog.probes.debug("Antigravity raw response: \(rawString.prefix(500))")
            }
            throw ProbeError.parseFailed("Invalid JSON: \(error.localizedDescription)")
        }

        let modelConfigs = response.userStatus?.cascadeModelConfigData?.clientModelConfigs ?? []
        AppLog.probes.debug("Antigravity: Found \(modelConfigs.count) model configs")

        let quotas = modelConfigs.compactMap { config -> UsageQuota? in
            guard let quotaInfo = config.quotaInfo,
                  let remainingFraction = quotaInfo.remainingFraction else {
                AppLog.probes.debug("Antigravity: Skipping model '\(config.label)' - no quota info")
                return nil
            }

            let resetsAt = quotaInfo.resetTime.flatMap { parseResetTime($0) }

            return UsageQuota(
                percentRemaining: remainingFraction * 100,
                quotaType: .modelSpecific(config.label),
                providerId: providerId,
                resetsAt: resetsAt
            )
        }

        guard !quotas.isEmpty else {
            AppLog.probes.error("Antigravity parse failed: No valid model quotas found in \(modelConfigs.count) configs")
            throw ProbeError.parseFailed("No valid model quotas found")
        }

        return UsageSnapshot(
            providerId: providerId,
            quotas: quotas,
            capturedAt: Date(),
            accountEmail: response.userStatus?.email
        )
    }

    /// Parses the CommandModel API response (fallback) into a UsageSnapshot
    static func parseCommandModelResponse(_ data: Data, providerId: String) throws -> UsageSnapshot {
        let decoder = JSONDecoder()

        let response: CommandModelResponse
        do {
            response = try decoder.decode(CommandModelResponse.self, from: data)
        } catch {
            throw ProbeError.parseFailed("Invalid JSON: \(error.localizedDescription)")
        }

        let modelConfigs = response.clientModelConfigs ?? []
        let quotas = modelConfigs.compactMap { config -> UsageQuota? in
            guard let quotaInfo = config.quotaInfo,
                  let remainingFraction = quotaInfo.remainingFraction else {
                return nil
            }

            let resetsAt = quotaInfo.resetTime.flatMap { parseResetTime($0) }

            return UsageQuota(
                percentRemaining: remainingFraction * 100,
                quotaType: .modelSpecific(config.label),
                providerId: providerId,
                resetsAt: resetsAt
            )
        }

        guard !quotas.isEmpty else {
            throw ProbeError.parseFailed("No valid model quotas found")
        }

        return UsageSnapshot(
            providerId: providerId,
            quotas: quotas,
            capturedAt: Date(),
            accountEmail: nil  // CommandModel response has no email
        )
    }

    // MARK: - Reset Time Parsing

    private static func parseResetTime(_ value: String) -> Date? {
        // Try ISO-8601 format first
        if let date = ISO8601DateFormatter().date(from: value) {
            return date
        }

        // Try epoch seconds
        if let seconds = Double(value) {
            return Date(timeIntervalSince1970: seconds)
        }

        return nil
    }
}

// MARK: - Response Models (Internal)

private struct UserStatusResponse: Decodable {
    let userStatus: UserStatus?
}

private struct UserStatus: Decodable {
    let email: String?
    let cascadeModelConfigData: ModelConfigData?
}

private struct ModelConfigData: Decodable {
    let clientModelConfigs: [ModelConfig]?
}

private struct CommandModelResponse: Decodable {
    let clientModelConfigs: [ModelConfig]?
}

private struct ModelConfig: Decodable {
    let label: String
    let modelOrAlias: ModelAlias
    let quotaInfo: QuotaInfo?
}

private struct ModelAlias: Decodable {
    let model: String
}

private struct QuotaInfo: Decodable {
    let remainingFraction: Double?
    let resetTime: String?
}

// MARK: - Insecure Session Delegate

/// URLSession delegate that accepts self-signed certificates for localhost connections.
/// This is required because Antigravity's local language server uses self-signed certs.
private final class InsecureLocalhostDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Only trust localhost connections
        guard let host = challenge.protectionSpace.host.lowercased() as String?,
              host == "127.0.0.1" || host == "localhost" else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Accept any certificate for localhost
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
