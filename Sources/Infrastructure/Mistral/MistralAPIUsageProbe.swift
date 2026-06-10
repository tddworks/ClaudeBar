import Foundation
import Domain

/// Probes Mistral Code API for Vibe Coding Plan usage percentage.
/// Calls `chat.mistral.ai/api/code-trpc/projects.list,apiKey.getApiKey,apiKey.getUsage`
/// with session cookie auth.
///
/// The response is NDJSON (newline-delimited JSON) where `apiKey.getUsage` returns
/// `{"usagePercentage": <0-100>, "resetAt": "ISO8601", ...}`.
///
/// Authentication: session cookie (`MISTRAL_CHAT_COOKIE` env var or browser cookies).
public struct MistralAPIUsageProbe: UsageProbe {
    private let networkClient: any NetworkClient
    private let settingsRepository: any MistralSettingsRepository
    private let timeout: TimeInterval

    private static let baseURL = "https://chat.mistral.ai"

    /// Procedures called in the batch tRPC request
    private static let procedures = "projects.list,apiKey.getApiKey,apiKey.getUsage"

    /// Input payload for each procedure
    private static var inputPayload: [String: Any] {
        [
            "0": ["json": ["direction": "forward"]],
            "1": ["json": NSNull(), "meta": ["values": ["undefined"], "v": 1]],
            "2": ["json": NSNull(), "meta": ["values": ["undefined"], "v": 1]],
        ]
    }

    public init(
        networkClient: any NetworkClient = URLSession.shared,
        settingsRepository: any MistralSettingsRepository,
        timeout: TimeInterval = 30
    ) {
        self.networkClient = networkClient
        self.settingsRepository = settingsRepository
        self.timeout = timeout
    }

    // MARK: - Cookie Resolution

    func getSessionCookie() -> String? {
        let envVarName = settingsRepository.mistralChatAuthEnvVar()
        let effectiveEnvVar = envVarName.isEmpty ? "MISTRAL_CHAT_COOKIE" : envVarName
        if let envValue = ProcessInfo.processInfo.environment[effectiveEnvVar], !envValue.isEmpty {
            AppLog.probes.debug("MistralAPI: Using session cookie from env var '\(effectiveEnvVar)'")
            return envValue
        }

        if let storedCookie = settingsRepository.getMistralChatCookie(), !storedCookie.isEmpty {
            AppLog.probes.debug("MistralAPI: Using stored session cookie")
            return storedCookie
        }

        return nil
    }

    // MARK: - UsageProbe

    public func isAvailable() async -> Bool {
        let hasCookie = getSessionCookie() != nil
        if !hasCookie {
            AppLog.probes.debug("MistralAPI: Not available - no session cookie configured")
        }
        return hasCookie
    }

    public func probe() async throws -> UsageSnapshot {
        guard let cookie = getSessionCookie(), !cookie.isEmpty else {
            AppLog.probes.error("MistralAPI: No session cookie configured (set MISTRAL_CHAT_COOKIE env var)")
            throw ProbeError.authenticationRequired
        }

        AppLog.probes.info("Starting MistralAPI probe...")

        let snapshot = try await fetchUsage(cookie: cookie)

        AppLog.probes.info("MistralAPI probe success: \(snapshot.quotas.count) quotas found")
        for quota in snapshot.quotas {
            AppLog.probes.info("  - \(quota.quotaType.displayName): \(Int(quota.percentRemaining))% remaining")
        }

        return snapshot
    }

    // MARK: - Chat API

    private func fetchUsage(cookie: String) async throws -> UsageSnapshot {
        guard var components = URLComponents(string: "\(Self.baseURL)/api/code-trpc/\(Self.procedures)") else {
            throw ProbeError.executionFailed("Invalid Mistral Chat URL")
        }

        let payload: [String: Any] = ["input": Self.inputPayload]
        let queryData = try JSONSerialization.data(withJSONObject: payload)
        guard let queryString = String(data: queryData, encoding: .utf8) else {
            throw ProbeError.executionFailed("Failed to encode query parameters")
        }

        components.queryItems = [
            URLQueryItem(name: "batch", value: "1"),
            URLQueryItem(name: "input", value: queryString),
        ]

        guard let url = components.url else {
            throw ProbeError.executionFailed("Failed to build request URL")
        }

        AppLog.probes.debug("MistralAPI: GET \(url.absoluteString.prefix(200))")
        AppLog.probes.debug("MistralAPI: Cookie(\(cookie.count) chars)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("application/jsonl", forHTTPHeaderField: "trpc-accept")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")

        let (data, response) = try await networkClient.request(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProbeError.executionFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            AppLog.probes.error("MistralAPI returned HTTP \(httpResponse.statusCode)")
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw ProbeError.authenticationRequired
            }
            throw ProbeError.executionFailed("Mistral Chat API returned HTTP \(httpResponse.statusCode)")
        }

        if let responseText = String(data: data, encoding: .utf8) {
            AppLog.probes.debug("MistralAPI response: \(responseText.prefix(500))")
        }

        return try Self.parseResponse(data, providerId: "mistral")
    }

    // MARK: - Response Parsing (Static for testability)

    static func parseResponse(_ data: Data, providerId: String) throws -> UsageSnapshot {
        let objects: [Any]
        if let array = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            objects = array
        } else if let text = String(data: data, encoding: .utf8) {
            objects = text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) }
            if objects.isEmpty {
                AppLog.probes.error("MistralAPI: Invalid JSON response")
                throw ProbeError.parseFailed("Invalid JSON response")
            }
        } else {
            throw ProbeError.parseFailed("Invalid response encoding")
        }

        for obj in objects {
            guard let dict = obj as? [String: Any],
                  let jsonVal = dict["json"] else { continue }
            if let usage = Self.findUsagePercentage(in: jsonVal) {
                let percentRemaining = max(0, 100.0 - usage.percentage)

                let resetsAt = usage.resetAt.flatMap { dateString in
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    if let date = formatter.date(from: dateString) { return date }
                    formatter.formatOptions = [.withInternetDateTime]
                    return formatter.date(from: dateString)
                }

                return UsageSnapshot(
                    providerId: providerId,
                    quotas: [
                        UsageQuota(
                            percentRemaining: percentRemaining,
                            quotaType: .timeLimit("Monthly"),
                            providerId: providerId,
                            resetsAt: resetsAt,
                            resetText: "\(Int(percentRemaining))% remaining"
                        )
                    ],
                    capturedAt: Date()
                )
            }
        }

        for obj in objects {
            if let dict = obj as? [String: Any],
               let error = dict["error"] as? String {
                AppLog.probes.error("MistralAPI: Error in response: \(error)")
                throw ProbeError.executionFailed("Mistral API error: \(error)")
            }
        }

        AppLog.probes.error("MistralAPI: No usage data found in response")
        throw ProbeError.noData
    }

    /// Recursively search for `usagePercentage` in arbitrarily nested JSON.
    static func findUsagePercentage(in value: Any) -> (percentage: Double, resetAt: String?)? {
        if let dict = value as? [String: Any],
           let pct = dict["usagePercentage"] as? Double {
            return (pct, dict["resetAt"] as? String)
        }
        if let arr = value as? [Any] {
            for element in arr {
                if let found = findUsagePercentage(in: element) {
                    return found
                }
            }
        }
        return nil
    }
}
