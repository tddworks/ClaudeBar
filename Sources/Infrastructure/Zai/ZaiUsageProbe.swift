import Foundation
import Domain

/// Z.ai platform detection
enum ZaiPlatform: String, Sendable {
    case zai = "https://api.z.ai"
    case zhipu = "https://open.bigmodel.cn"
    case dev = "https://dev.bigmodel.cn"
}

/// Probes the z.ai GLM Coding Plan for usage quota information.
/// Z.ai works as an API-compatible replacement for Anthropic's API,
/// configured through Claude Code's settings file.
public struct ZaiUsageProbe: UsageProbe {
    private let cliExecutor: any CLIExecutor
    private let networkClient: any NetworkClient
    private let settingsRepository: any ZaiSettingsRepository
    private let timeout: TimeInterval

    // Claude config file location
    private static let defaultConfigPath = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".claude")
        .appendingPathComponent("settings.json")

    /// Creates a new Z.ai usage probe
    /// - Parameters:
    ///   - cliExecutor: Executor for running CLI commands (defaults to DefaultCLIExecutor)
    ///   - networkClient: Client for making network requests (defaults to URLSession.shared)
    ///   - settingsRepository: Repository for Z.ai settings (required, explicit injection)
    ///   - timeout: Timeout for operations in seconds (defaults to 10.0)
    public init(
        cliExecutor: (any CLIExecutor)? = nil,
        networkClient: (any NetworkClient)? = nil,
        settingsRepository: any ZaiSettingsRepository,
        timeout: TimeInterval = 10.0
    ) {
        self.cliExecutor = cliExecutor ?? DefaultCLIExecutor()
        self.networkClient = networkClient ?? URLSession.shared
        self.settingsRepository = settingsRepository
        self.timeout = timeout
    }

    // MARK: - UsageProbe

    /// Checks if Z.ai is available by looking for Claude CLI and z.ai configuration
    public func isAvailable() async -> Bool {
        // Check if Claude CLI is installed
        guard cliExecutor.locate("claude") != nil else {
            let env = ProcessInfo.processInfo.environment
            AppLog.probes.info("Zai: Claude CLI not found")
            AppLog.probes.info("Current directory: \(FileManager.default.currentDirectoryPath)")
            AppLog.probes.info("PATH: \(env["PATH"] ?? "<not set>")")
            return false
        }

        // Check if z.ai is configured in Claude settings
        do {
            let (config, _) = try await readClaudeConfig()
            return Self.hasZaiEndpoint(in: config)
        } catch {
            AppLog.probes.debug("Zai: Could not read Claude config: \(error.localizedDescription)")
            return false
        }
    }

    /// Fetches the current usage quota from Z.ai API
    public func probe() async throws -> UsageSnapshot {
        guard cliExecutor.locate("claude") != nil else {
            AppLog.probes.error("Zai probe failed: Claude CLI not found")
            throw ProbeError.cliNotFound("Claude")
        }

        let (config, configPath): (String, String)
        do {
            (config, configPath) = try await readClaudeConfig()
        } catch {
            AppLog.probes.error("Zai probe failed: Could not read Claude config: \(error.localizedDescription)")
            throw ProbeError.executionFailed("Could not read Claude config")
        }

        guard let platform = Self.detectPlatform(from: config) else {
            AppLog.probes.error("Zai probe failed: No z.ai endpoint found in Claude config (path: \(configPath))")
            throw ProbeError.authenticationRequired
        }

        let apiKey = try extractAPIKeyWithFallback(from: config, configPath: configPath)
        AppLog.probes.debug("Zai: Detected platform: \(platform.rawValue)")

        let baseURL = platform.rawValue
        guard let url = URL(string: "\(baseURL)/api/monitor/usage/quota/limit") else {
            AppLog.probes.error("Zai probe failed: Invalid API URL")
            throw ProbeError.executionFailed("Invalid API URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("en-US,en", forHTTPHeaderField: "Accept-Language")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await networkClient.request(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            AppLog.probes.error("Zai probe failed: Invalid HTTP response")
            throw ProbeError.executionFailed("Invalid HTTP response")
        }

        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401, 403:
            AppLog.probes.error("Zai probe failed: Authentication failed (HTTP \(httpResponse.statusCode))")
            throw ProbeError.authenticationRequired
        default:
            AppLog.probes.error("Zai probe failed: API returned HTTP \(httpResponse.statusCode)")
            throw ProbeError.executionFailed("API returned HTTP \(httpResponse.statusCode)")
        }

        // Log raw response at debug level
        if let responseText = String(data: data, encoding: .utf8) {
            AppLog.probes.debug("Zai API response: \(responseText.prefix(500))")
        }

        // Step 7: Parse response
        let snapshot = try Self.parseQuotaLimitResponse(data, providerId: "zai")

        AppLog.probes.info("Zai probe success: \(snapshot.quotas.count) quotas found")
        for quota in snapshot.quotas {
            AppLog.probes.info("  - \(quota.quotaType.displayName): \(Int(quota.percentRemaining))% remaining")
        }

        return snapshot
    }

    // MARK: - Configuration Reading

    private func readClaudeConfig() async throws -> (config: String, path: String) {
        let configPath: URL
        let customPath = settingsRepository.zaiConfigPath()
        if !customPath.isEmpty {
            configPath = URL(fileURLWithPath: customPath)
        } else {
            configPath = Self.defaultConfigPath
        }
        AppLog.probes.debug("Using Z.ai config path: \(configPath.path)")

        let result = try cliExecutor.execute(
            binary: "cat",
            args: [configPath.path],
            input: nil,
            timeout: timeout,
            workingDirectory: nil,
            autoResponses: [:]
        )

        return (result.output, configPath.path)
    }

    private func extractAPIKeyWithFallback(from config: String, configPath: String) throws -> String {
        if let configApiKey = Self.extractAPIKey(from: config) {
            AppLog.probes.debug("Zai: Using API key from config file")
            return configApiKey
        }

        let envVarName = settingsRepository.glmAuthEnvVar()
        guard !envVarName.isEmpty else {
            AppLog.probes.error("Zai probe failed: No API key found (config file: \(configPath), env var: not set)")
            throw ProbeError.authenticationRequired
        }

        guard let envValue = ProcessInfo.processInfo.environment[envVarName], !envValue.isEmpty else {
            AppLog.probes.error("Zai probe failed: No API key found (config file: \(configPath), env var: \(envVarName) not set)")
            throw ProbeError.authenticationRequired
        }

        AppLog.probes.debug("Zai: API key not in config, using env var '\(envVarName)'")
        return envValue
    }

    // MARK: - Static Parsing Helpers

    /// Checks if the Claude config contains a z.ai endpoint
    internal static func hasZaiEndpoint(in config: String) -> Bool {
        guard let platform = detectPlatform(from: config) else {
            return false
        }
        return platform == .zai || platform == .zhipu || platform == .dev
    }

    /// Detects the z.ai platform from Claude config
    internal static func detectPlatform(from config: String) -> ZaiPlatform? {
        guard let data = config.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Check env.ANTHROPIC_BASE_URL format (Claude Code default)
        if let env = json["env"] as? [String: Any],
           let baseURL = env["ANTHROPIC_BASE_URL"] as? String {
            if baseURL.contains("api.z.ai") {
                return .zai
            }
            if baseURL.contains("open.bigmodel.cn") {
                return .zhipu
            }
            if baseURL.contains("dev.bigmodel.cn") {
                return .dev
            }
        }

        // Check providers array format
        if let providers = json["providers"] as? [[String: Any]] {
            for provider in providers {
                if let baseURL = provider["base_url"] as? String {
                    if baseURL.contains("api.z.ai") {
                        return .zai
                    }
                    if baseURL.contains("open.bigmodel.cn") {
                        return .zhipu
                    }
                    if baseURL.contains("dev.bigmodel.cn") {
                        return .dev
                    }
                }
            }
        }

        // Fallback: check for any key with z.ai URL
        let jsonStr = config.lowercased()
        if jsonStr.contains("api.z.ai") {
            return .zai
        }
        if jsonStr.contains("open.bigmodel.cn") {
            return .zhipu
        }
        if jsonStr.contains("dev.bigmodel.cn") {
            return .dev
        }

        return nil
    }

    /// Extracts the API key from Claude config
    internal static func extractAPIKey(from config: String) -> String? {
        guard let data = config.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Check env.ANTHROPIC_AUTH_TOKEN format (Claude Code default)
        if let env = json["env"] as? [String: Any],
           let authToken = env["ANTHROPIC_AUTH_TOKEN"] as? String,
           !authToken.isEmpty {
            return authToken
        }

        // Check providers array for api_key
        if let providers = json["providers"] as? [[String: Any]] {
            for provider in providers {
                if let apiKey = provider["api_key"] as? String, !apiKey.isEmpty {
                    return apiKey
                }
            }
        }

        // Check for direct api_key field
        if let apiKey = json["api_key"] as? String, !apiKey.isEmpty {
            return apiKey
        }

        return nil
    }

    // MARK: - Response Parsing (Static for testability)

    /// Parses the quota limit API response into a UsageSnapshot
    internal static func parseQuotaLimitResponse(_ data: Data, providerId: String) throws -> UsageSnapshot {
        let decoder = JSONDecoder()

        let response: QuotaLimitResponse
        do {
            response = try decoder.decode(QuotaLimitResponse.self, from: data)
        } catch {
            AppLog.probes.error("Zai parse failed: Invalid JSON - \(error.localizedDescription)")
            if let rawString = String(data: data, encoding: .utf8) {
                AppLog.probes.debug("Zai raw response: \(rawString.prefix(500))")
            }
            throw ProbeError.parseFailed("Invalid JSON: \(error.localizedDescription)")
        }

        guard let limits = response.data?.limits, !limits.isEmpty else {
            AppLog.probes.error("Zai parse failed: No quota limits found in response")
            throw ProbeError.parseFailed("No quota limits found")
        }

        var quotas: [UsageQuota] = []

        for limit in limits {
            let quotaType: QuotaType
            let percentageUsed = limit.percentage

            switch limit.type {
            case "TOKENS_LIMIT":
                quotaType = .session
            case "TIME_LIMIT":
                quotaType = .timeLimit("MCP")
            default:
                // Skip unknown limit types
                continue
            }

            // Clamp percentage to 0-100 range
            let clampedUsed = max(0, min(100, percentageUsed))
            let percentRemaining = 100.0 - Double(clampedUsed)

            let resetsAt = Self.parseResetDate(limit.nextResetTime)

            quotas.append(UsageQuota(
                percentRemaining: percentRemaining,
                quotaType: quotaType,
                providerId: providerId,
                resetsAt: resetsAt
            ))
        }

        guard !quotas.isEmpty else {
            AppLog.probes.error("Zai parse failed: No recognized quota types found")
            throw ProbeError.parseFailed("No recognized quota types found")
        }

        return UsageSnapshot(
            providerId: providerId,
            quotas: quotas,
            capturedAt: Date()
        )
    }

    /// Parses the reset date from API value (can be Int64 ms or ISO-8601 string)
    internal static func parseResetDate(_ value: FlexibleDate?) -> Date? {
        guard let value else { return nil }

        switch value {
        case .timestamp(let ms):
            return Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        case .string(let text):
            // Try ISO-8601 first
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFormatter.date(from: text) {
                return date
            }

            // Fallback to standard ISO without fractional seconds
            isoFormatter.formatOptions = [.withInternetDateTime]
            if let date = isoFormatter.date(from: text) {
                return date
            }

            // Check if string contains a number (epoch)
            if let seconds = Double(text) {
                return Date(timeIntervalSince1970: seconds)
            }

            return nil
        }
    }
}

// MARK: - Response Models

private struct QuotaLimitResponse: Decodable {
    let data: QuotaLimitData?
}

private struct QuotaLimitData: Decodable {
    let limits: [QuotaLimit]?
}

private struct QuotaLimit: Decodable {
    let type: String
    let percentage: Double
    let nextResetTime: FlexibleDate?
}

/// A type that can be decoded from either a number (timestamp) or a string (ISO date)
internal enum FlexibleDate: Decodable {
    case timestamp(Int64)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let ms = try? container.decode(Int64.self) {
            self = .timestamp(ms)
        } else if let str = try? container.decode(String.self) {
            self = .string(str)
        } else {
            throw DecodingError.typeMismatch(
                FlexibleDate.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected Int64 or String")
            )
        }
    }
}
