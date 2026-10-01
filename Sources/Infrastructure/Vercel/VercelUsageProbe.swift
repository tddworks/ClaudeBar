import Foundation
import Domain

/// Probes Vercel AI Gateway for the team's credits balance.
/// Authentication: Bearer token from env var (AI_GATEWAY_API_KEY) or stored API key.
/// Data source: GET https://ai-gateway.vercel.sh/v1/credits
public struct VercelUsageProbe: UsageProbe {
    private let networkClient: any NetworkClient
    private let settingsRepository: any VercelSettingsRepository
    private let timeout: TimeInterval
    private let environment: [String: String]

    /// The AI Gateway credits balance endpoint
    var apiURL: URL {
        URL(string: "https://ai-gateway.vercel.sh/v1/credits")!
    }

    public init(
        networkClient: any NetworkClient = URLSession.shared,
        settingsRepository: any VercelSettingsRepository,
        timeout: TimeInterval = 30,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.networkClient = networkClient
        self.settingsRepository = settingsRepository
        self.timeout = timeout
        self.environment = environment
    }

    // MARK: - Token Resolution

    func getApiKey() -> String? {
        // First, check environment variable if configured
        let envVarName = settingsRepository.vercelAuthEnvVar()
        let effectiveEnvVar = envVarName.isEmpty ? "AI_GATEWAY_API_KEY" : envVarName
        if let envValue = normalizedApiKey(environment[effectiveEnvVar]) {
            AppLog.probes.debug("Vercel: Using API key from env var '\(effectiveEnvVar)'")
            return envValue
        }

        // Fall back to stored API key
        if let storedKey = normalizedApiKey(settingsRepository.getVercelApiKey()) {
            AppLog.probes.debug("Vercel: Using stored API key")
            return storedKey
        }

        return nil
    }

    private func normalizedApiKey(_ value: String?) -> String? {
        guard let key = value?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            return nil
        }
        return key
    }

    // MARK: - UsageProbe

    public func isAvailable() async -> Bool {
        let hasKey = getApiKey() != nil
        if !hasKey {
            AppLog.probes.debug("Vercel: Not available - no API key configured")
        }
        return hasKey
    }

    public func probe() async throws -> UsageSnapshot {
        guard let apiKey = getApiKey(), !apiKey.isEmpty else {
            AppLog.probes.error("Vercel: No API key configured (check env var or settings)")
            throw ProbeError.authenticationRequired
        }

        AppLog.probes.info("Starting Vercel AI Gateway probe...")

        var request = URLRequest(url: apiURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = timeout

        let (data, response) = try await networkClient.request(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProbeError.executionFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            AppLog.probes.error("Vercel API returned HTTP \(httpResponse.statusCode)")
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw ProbeError.authenticationRequired
            }
            throw ProbeError.executionFailed("Vercel API returned HTTP \(httpResponse.statusCode)")
        }

        AppLog.probes.debug("Vercel API response received (\(data.count) bytes)")

        let snapshot = try Self.parseResponse(data, providerId: "vercel-gateway")

        AppLog.probes.info("Vercel probe success: \(snapshot.quotas.count) quotas found")
        for quota in snapshot.quotas {
            AppLog.probes.info("  - \(quota.quotaType.displayName) balance received")
        }

        return snapshot
    }

    // MARK: - Response Parsing (Static for testability)

    /// Parses the AI Gateway credits response into a UsageSnapshot.
    /// Response: `{ "balance": 95.50, "total_used": 4.50 }` — both in USD.
    /// Numeric strings are also accepted for compatibility with gateway-compatible APIs.
    /// Maps to a single dollar-based balance quota (AmpCode pattern) since there
    /// is no total cap to derive a percentage from.
    static func parseResponse(_ data: Data, providerId: String) throws -> UsageSnapshot {
        struct CreditsResponse: Decodable {
            let balance: FlexibleDecimal?
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let response: CreditsResponse
        do {
            response = try decoder.decode(CreditsResponse.self, from: data)
        } catch {
            AppLog.probes.error("Vercel parse failed: Invalid JSON - \(error.localizedDescription)")
            throw ProbeError.parseFailed("Invalid JSON: \(error.localizedDescription)")
        }

        guard let balance = response.balance?.value else {
            AppLog.probes.error("Vercel: Invalid or missing balance in response")
            throw ProbeError.parseFailed("Invalid or missing balance")
        }

        let quota = UsageQuota(
            percentRemaining: 100,
            quotaType: .timeLimit("AI Gateway Credits"),
            providerId: providerId,
            dollarRemaining: balance
        )

        return UsageSnapshot(
            providerId: providerId,
            quotas: [quota],
            capturedAt: Date()
        )
    }
}

private struct FlexibleDecimal: Decodable {
    let value: Decimal

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let number = try? container.decode(Decimal.self) {
            value = number
            return
        }

        let string = try container.decode(String.self)
        guard let number = Decimal(
            string: string,
            locale: Locale(identifier: "en_US_POSIX")
        ) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a decimal number or numeric string"
            )
        }
        value = number
    }
}
