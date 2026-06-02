import Foundation
import Domain

/// Probe for fetching GitHub Copilot usage data via Copilot Internal API.
///
/// Uses the Copilot Internal API to fetch quota data:
/// `GET https://api.github.com/copilot_internal/user`
///
/// Works for all plan types (Free, Pro, Business, Enterprise).
/// Requires a Classic PAT with "copilot" scope.
public struct CopilotInternalAPIProbe: UsageProbe {
    private let networkClient: any NetworkClient
    private let settingsRepository: any CopilotSettingsRepository
    private let timeout: TimeInterval

    private static let apiBaseURL = "https://api.github.com"

    public init(
        networkClient: any NetworkClient = URLSession.shared,
        settingsRepository: any CopilotSettingsRepository,
        timeout: TimeInterval = 30
    ) {
        self.networkClient = networkClient
        self.settingsRepository = settingsRepository
        self.timeout = timeout
    }

    // MARK: - Token Resolution

    private func getToken() -> String? {
        // First, check environment variable if configured
        let envVarName = settingsRepository.copilotAuthEnvVar()
        if !envVarName.isEmpty {
            if let envValue = ProcessInfo.processInfo.environment[envVarName], !envValue.isEmpty {
                AppLog.probes.debug("Copilot Internal API: Using token from env var '\(envVarName)'")
                return envValue
            }
        }

        // Fall back to stored token
        if let storedToken = settingsRepository.getGithubToken(), !storedToken.isEmpty {
            AppLog.probes.debug("Copilot Internal API: Using stored token")
            return storedToken
        }

        return nil
    }

    public func isAvailable() async -> Bool {
        // Copilot Internal API only needs a token (no username required)
        guard let token = getToken(), !token.isEmpty else {
            AppLog.probes.debug("Copilot Internal API: Not available - missing token")
            return false
        }
        return true
    }

    public func probe() async throws -> UsageSnapshot {
        guard let token = getToken(), !token.isEmpty else {
            AppLog.probes.error("Copilot Internal API: No GitHub token configured (check token field or env var)")
            throw ProbeError.authenticationRequired
        }

        AppLog.probes.debug("Copilot Internal API: Fetching user quota data")

        let userData = try await fetchCopilotUser(token: token)
        return try parseUserResponse(userData)
    }

    // MARK: - API Call

    private func fetchCopilotUser(token: String) async throws -> CopilotInternalUserResponse {
        let urlString = "\(Self.apiBaseURL)/copilot_internal/user"

        guard let url = URL(string: urlString) else {
            throw ProbeError.executionFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = timeout

        let (data, response) = try await networkClient.request(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProbeError.executionFailed("Invalid response")
        }

        AppLog.probes.debug("Copilot Internal API response status: \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            AppLog.probes.error("Copilot Internal API: Authentication failed (401)")
            throw ProbeError.authenticationRequired
        case 403:
            AppLog.probes.error("Copilot Internal API: Forbidden - check token permissions (403)")
            throw ProbeError.executionFailed("Forbidden - ensure Classic PAT has 'copilot' scope")
        case 404:
            AppLog.probes.error("Copilot Internal API: Endpoint not found or no Copilot subscription (404)")
            throw ProbeError.executionFailed("No Copilot subscription found")
        default:
            AppLog.probes.error("Copilot Internal API: HTTP error \(httpResponse.statusCode)")
            throw ProbeError.executionFailed("HTTP error: \(httpResponse.statusCode)")
        }

        // Log response metadata for debugging (avoid logging full response body)
        AppLog.probes.debug("Copilot Internal API: received \(data.count) bytes")

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(CopilotInternalUserResponse.self, from: data)
        } catch {
            AppLog.probes.error("Copilot Internal API: Failed to parse response - \(error.localizedDescription)")
            throw ProbeError.parseFailed("Failed to parse Copilot Internal API response: \(error.localizedDescription)")
        }
    }

    // MARK: - Response Parsing

    private func parseUserResponse(_ response: CopilotInternalUserResponse) throws -> UsageSnapshot {
        let plan = response.copilotPlan ?? "unknown"
        AppLog.probes.debug("Copilot Internal API: Plan type = \(plan)")

        // Look for premium_interactions quota
        guard let premiumInteractions = response.quotaSnapshots?.premiumInteractions else {
            AppLog.probes.info("Copilot Internal API: No premium_interactions quota found (plan may only include chat/completions)")
            // Return 100% remaining if no premium interactions quota exists
            let quota = UsageQuota(
                percentRemaining: 100,
                quotaType: .timeLimit("Monthly"),
                providerId: "copilot",
                resetsAt: MonthlyResetDate.nextMonthlyResetDate(),
                resetText: "No AI credits quota"
            )
            return UsageSnapshot(
                providerId: "copilot",
                quotas: [quota],
                capturedAt: Date(),
                accountEmail: plan
            )
        }

        // Handle unlimited premium interactions
        if premiumInteractions.unlimited == true {
            AppLog.probes.info("Copilot Internal API: Unlimited premium interactions")
            let quota = UsageQuota(
                percentRemaining: 100,
                quotaType: .timeLimit("Monthly"),
                providerId: "copilot",
                resetsAt: MonthlyResetDate.nextMonthlyResetDate(),
                resetText: "Unlimited AI credits"
            )
            return UsageSnapshot(
                providerId: "copilot",
                quotas: [quota],
                capturedAt: Date(),
                accountEmail: plan
            )
        }

        let entitlement = premiumInteractions.entitlement ?? 0
        let remaining = premiumInteractions.remaining ?? 0
        let percentRemaining = premiumInteractions.percentRemaining ?? 100

        // Calculate used from entitlement - remaining (clamp to non-negative)
        let used = max(0, entitlement - remaining)

        AppLog.probes.debug("Copilot Internal API: Used \(used)/\(entitlement) AI credits, \(Int(percentRemaining))% remaining")

        let resetText = "\(used)/\(entitlement) AI credits"

        let quota = UsageQuota(
            percentRemaining: percentRemaining,
            quotaType: .timeLimit("Monthly"),
            providerId: "copilot",
            resetsAt: MonthlyResetDate.nextMonthlyResetDate(),
            resetText: resetText
        )

        return UsageSnapshot(
            providerId: "copilot",
            quotas: [quota],
            capturedAt: Date(),
            accountEmail: plan
        )
    }
}

// MARK: - API Response Models

/// Response from GET /copilot_internal/user
struct CopilotInternalUserResponse: Decodable {
    let copilotPlan: String?
    let quotaResetDate: String?
    let quotaSnapshots: QuotaSnapshots?
    let quotaResetDateUtc: String?

    struct QuotaSnapshots: Decodable {
        let premiumInteractions: InteractionQuota?
    }

    struct InteractionQuota: Decodable {
        let entitlement: Int?
        let percentRemaining: Double?
        let remaining: Int?
        let unlimited: Bool?
        let overageCount: Int?
        let overagePermitted: Bool?
    }
}
