import Foundation
import Domain

/// Probes Antigravity for usage quota information.
///
/// Sources, best first:
/// 1. The local language server of the running Antigravity app or `agy` CLI (loopback API).
/// 2. With nothing running, the OAuth access token Antigravity / `agy` stored in the Keychain,
///    used against Google's Cloud Code API — so the desktop app need not stay open (#201).
///    The token is not refreshed here; once it expires the user is asked to sign in again.
public struct AntigravityUsageProbe: UsageProbe {

    private let cliExecutor: any CLIExecutor
    private let networkClient: any NetworkClient
    private let cloudClient: AntigravityCloudCodeClient
    private let credentialLoader: AntigravityKeychainCredentialLoader
    private let timeout: TimeInterval
    private let now: @Sendable () -> Date

    // Match the app's language server (current and older names) and the `agy` CLI.
    private static let processNames = ["language_server", "language_server_macos", "language_server_macos_arm", "agy"]

    static let sessionExpiredHint = "Sign in to Antigravity or run `agy` again."

    public init(
        cliExecutor: (any CLIExecutor)? = nil,
        networkClient: (any NetworkClient)? = nil,
        remoteNetworkClient: (any NetworkClient)? = nil,
        timeout: TimeInterval = 8.0,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        let executor = cliExecutor ?? DefaultCLIExecutor()
        self.cliExecutor = executor
        // Use insecure client by default for self-signed localhost certificates
        self.networkClient = networkClient ?? InsecureLocalhostNetworkClient(timeout: timeout)
        // Remote calls use full TLS validation
        self.cloudClient = AntigravityCloudCodeClient(networkClient: remoteNetworkClient ?? URLSession.shared)
        self.credentialLoader = AntigravityKeychainCredentialLoader(cliExecutor: executor, timeout: timeout)
        self.timeout = timeout
        self.now = now
    }

    // MARK: - UsageProbe

    public func isAvailable() async -> Bool {
        do {
            let processInfo = try await detectProcess()
            AppLog.probes.debug("Antigravity process detected: PID=\(processInfo.pid)")
            return true
        } catch {
            AppLog.probes.debug("Antigravity process not available: \(error.localizedDescription)")
        }

        if await credentialLoader.load() != nil {
            AppLog.probes.debug("Antigravity: Keychain credentials found, Cloud Code fallback available")
            return true
        }
        return false
    }

    public func probe() async throws -> UsageSnapshot {
        AppLog.probes.info("Starting Antigravity probe...")

        // Step 1: Detect running Antigravity process
        let processInfo: ProcessInfo
        do {
            processInfo = try await detectProcess()
            AppLog.probes.debug("Antigravity process found: PID=\(processInfo.pid), port=\(processInfo.extensionPort ?? 0)")
        } catch ProbeError.cliNotFound {
            AppLog.probes.info("Antigravity not running; trying Cloud Code with stored credentials")
            return try await probeCloudCode()
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

        // Step 4: Parse response — pooled quota summary first, legacy per-model status otherwise
        let snapshot: UsageSnapshot
        if let quotas = AntigravityQuotaSummaryParser.parse(data, providerId: "antigravity"), !quotas.isEmpty {
            snapshot = UsageSnapshot(providerId: "antigravity", quotas: quotas, capturedAt: now())
        } else {
            snapshot = try Self.parseUserStatusResponse(data, providerId: "antigravity")
        }

        logSuccess(snapshot)
        return snapshot
    }

    private func logSuccess(_ snapshot: UsageSnapshot) {
        AppLog.probes.info("Antigravity probe success: \(snapshot.quotas.count) quotas found, email=\(snapshot.accountEmail ?? "none")")
        for quota in snapshot.quotas {
            AppLog.probes.info("  - \(quota.quotaType.displayName): \(Int(quota.percentRemaining))% remaining")
        }
    }

    // MARK: - Cloud Code Fallback (app closed)

    private func probeCloudCode() async throws -> UsageSnapshot {
        guard let credentials = await credentialLoader.load() else {
            AppLog.probes.error("Antigravity probe failed: not running and no stored credentials")
            throw ProbeError.cliNotFound("Antigravity")
        }

        guard credentials.hasUsableAccessToken(at: now()), let token = credentials.accessToken else {
            AppLog.probes.error("Antigravity: stored access token is expired; run Antigravity or agy to refresh it")
            throw ProbeError.sessionExpired(hint: Self.sessionExpiredHint)
        }

        switch await fetchCloudQuota(token: token) {
        case .snapshot(let snapshot):
            logSuccess(snapshot)
            return snapshot
        case .authFailed:
            AppLog.probes.error("Antigravity: Cloud Code rejected the stored access token")
            throw ProbeError.sessionExpired(hint: Self.sessionExpiredHint)
        case .unavailable:
            AppLog.probes.error("Antigravity: Cloud Code quota endpoints unavailable")
            throw ProbeError.executionFailed("Could not reach the Antigravity quota API")
        }
    }

    private enum CloudQuotaResult {
        case snapshot(UsageSnapshot)
        case authFailed
        case unavailable
    }

    private func fetchCloudQuota(token: String) async -> CloudQuotaResult {
        // Authoritative: pooled summary (both pools, 5h + weekly windows)
        switch await cloudClient.post(path: AntigravityCloudCodeClient.quotaSummaryPath, token: token) {
        case .authFailed:
            return .authFailed
        case .ok(let data):
            if let quotas = AntigravityQuotaSummaryParser.parse(data, providerId: "antigravity"), !quotas.isEmpty {
                return .snapshot(UsageSnapshot(
                    providerId: "antigravity",
                    quotas: quotas,
                    capturedAt: now(),
                    accountTier: await loadPlan(token: token)
                ))
            }
        case .unavailable:
            break
        }

        // Legacy: per-model quotas (5h windows only)
        switch await cloudClient.post(path: AntigravityCloudCodeClient.fetchModelsPath, token: token) {
        case .authFailed:
            return .authFailed
        case .ok(let data):
            let quotas = Self.parseAvailableModels(data, providerId: "antigravity")
            if !quotas.isEmpty {
                return .snapshot(UsageSnapshot(
                    providerId: "antigravity",
                    quotas: quotas,
                    capturedAt: now(),
                    accountTier: await loadPlan(token: token)
                ))
            }
        case .unavailable:
            break
        }
        return .unavailable
    }

    private func loadPlan(token: String) async -> AccountTier? {
        guard case .ok(let data) = await cloudClient.post(path: AntigravityCloudCodeClient.loadCodeAssistPath, token: token) else {
            return nil
        }
        return Self.parsePlanName(data).map { .custom($0.uppercased()) }
    }

    // MARK: - Process Detection

    private struct ProcessInfo {
        let pid: Int
        let csrfToken: String
        let extensionPort: Int?
    }

    private func detectProcess() async throws -> ProcessInfo {
        // Use pgrep for more reliable process detection (avoids PTY buffering issues)
        let output: String
        do {
            output = try await cliExecutor.execute(
                binary: "/usr/bin/pgrep",
                args: ["-lf", "language_server"],
                input: nil,
                timeout: timeout,
                workingDirectory: nil,
                autoResponses: [:]
            ).output
        } catch InteractiveRunner.RunError.timedOut {
            // pgrep matching nothing exits with empty output, which the PTY runner
            // reports as a timeout. That means "not running" (#301).
            output = ""
        }

        // Handle different line endings
        let normalizedOutput = output
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalizedOutput.split(separator: "\n", omittingEmptySubsequences: true)

        AppLog.probes.debug("Antigravity: pgrep returned \(lines.count) matching processes")

        for line in lines {
            let lineStr = String(line).trimmingCharacters(in: .whitespaces)
            guard Self.isAntigravityProcess(lineStr) else { continue }

            guard let pid = Self.extractPID(from: lineStr) else { continue }

            AppLog.probes.debug("Antigravity: Checking process (length=\(lineStr.count)): \(lineStr.prefix(200))...")

            if let csrfToken = Self.extractCSRFToken(from: lineStr) {
                let extensionPort = Self.extractExtensionPort(from: lineStr)
                AppLog.probes.debug("Antigravity process detected: PID=\(pid), hasCSRF=true, extPort=\(extensionPort ?? 0)")
                return ProcessInfo(pid: pid, csrfToken: csrfToken, extensionPort: extensionPort)
            } else {
                AppLog.probes.error("Antigravity process found (PID=\(pid)) but missing CSRF token")
                AppLog.probes.debug("Antigravity: Full command line: \(lineStr)")
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

        let result = try await cliExecutor.execute(
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
            "/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary",
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

        // Use network client (insecure by default for self-signed localhost certs)
        let (data, response) = try await networkClient.request(request)

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
        // The `agy` CLI binary (e.g. "/opt/homebrew/bin/agy --csrf_token ...")
        if lower.range(of: #"(^|/|\s)agy(\s|$)"#, options: .regularExpression) != nil {
            return true
        }
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
            guard let quotaInfo = config.quotaInfo else {
                AppLog.probes.debug("Antigravity: Skipping model '\(config.label)' - no quota info")
                return nil
            }

            // Missing remainingFraction means 0% remaining (quota exhausted)
            let remainingFraction = quotaInfo.remainingFraction ?? 0.0
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

        // Extract account tier from planName (e.g., "Pro" → .custom("PRO"))
        let accountTier: AccountTier? = response.userStatus?.planStatus?.planInfo?.planName.map {
            .custom($0.uppercased())
        }

        return UsageSnapshot(
            providerId: providerId,
            quotas: quotas,
            capturedAt: Date(),
            accountEmail: response.userStatus?.email,
            accountTier: accountTier
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
            guard let quotaInfo = config.quotaInfo else {
                return nil
            }

            // Missing remainingFraction means 0% remaining (quota exhausted)
            let remainingFraction = quotaInfo.remainingFraction ?? 0.0
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

    // MARK: - Cloud Code Parsing (Static for testability)

    /// Parses Cloud Code `fetchAvailableModels` into per-model quotas (internal models dropped).
    static func parseAvailableModels(_ data: Data, providerId: String) -> [UsageQuota] {
        guard let response = try? JSONDecoder().decode(AvailableModelsResponse.self, from: data),
              let models = response.models else {
            return []
        }
        return models
            .sorted { $0.key < $1.key }
            .compactMap { key, model -> UsageQuota? in
                if model.isInternal == true { return nil }
                guard let quotaInfo = model.quotaInfo else { return nil }
                let label = [model.displayName, model.label, key]
                    .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
                    .first { !$0.isEmpty } ?? key
                return UsageQuota(
                    percentRemaining: (quotaInfo.remainingFraction ?? 0.0) * 100,
                    quotaType: .modelSpecific(label),
                    providerId: providerId,
                    resetsAt: quotaInfo.resetTime.flatMap { parseResetTime($0) }
                )
            }
    }

    /// Parses Cloud Code `loadCodeAssist` for the subscription tier name.
    static func parsePlanName(_ data: Data) -> String? {
        guard let response = try? JSONDecoder().decode(LoadCodeAssistResponse.self, from: data) else { return nil }
        let name = (response.paidTier?.name ?? response.currentTier?.name)?.trimmingCharacters(in: .whitespaces)
        guard let name, !name.isEmpty else { return nil }
        return name
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
    let planStatus: PlanStatus?
}

private struct PlanStatus: Decodable {
    let planInfo: PlanInfo?
}

private struct PlanInfo: Decodable {
    let planName: String?
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

private struct AvailableModelsResponse: Decodable {
    let models: [String: AvailableModel]?
}

private struct AvailableModel: Decodable {
    let displayName: String?
    let label: String?
    let isInternal: Bool?
    let quotaInfo: QuotaInfo?
}

private struct LoadCodeAssistResponse: Decodable {
    let paidTier: Tier?
    let currentTier: Tier?

    struct Tier: Decodable {
        let name: String?
    }
}
