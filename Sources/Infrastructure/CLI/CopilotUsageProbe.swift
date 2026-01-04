import Foundation
import Domain

/// Probe for fetching GitHub Copilot usage data via GitHub Billing API.
///
/// Uses the GitHub REST API to fetch premium request usage:
/// `GET /users/{username}/settings/billing/usage`
///
/// Requires a fine-grained PAT with "Plan: read" permission.
public struct CopilotUsageProbe: UsageProbe {
    private let networkClient: any NetworkClient
    private let credentialRepository: any CredentialRepository
    private let configRepository: any ProviderConfigRepository
    private let timeout: TimeInterval

    private static let apiBaseURL = "https://api.github.com"
    private static let apiVersion = "2022-11-28"

    public init(
        networkClient: any NetworkClient = URLSession.shared,
        credentialRepository: any CredentialRepository = UserDefaultsCredentialRepository.shared,
        configRepository: any ProviderConfigRepository = UserDefaultsProviderConfigRepository.shared,
        timeout: TimeInterval = 30
    ) {
        self.networkClient = networkClient
        self.credentialRepository = credentialRepository
        self.configRepository = configRepository
        self.timeout = timeout
    }

    // MARK: - Token Resolution

    private func getToken() -> String? {
        // First, check environment variable if configured
        let envVarName = configRepository.copilotAuthEnvVar()
        if !envVarName.isEmpty {
            if let envValue = ProcessInfo.processInfo.environment[envVarName], !envValue.isEmpty {
                AppLog.probes.debug("Copilot: Using token from env var '\(envVarName)'")
                return envValue
            }
        }

        // Fall back to stored token
        if let storedToken = credentialRepository.get(forKey: CredentialKey.githubToken), !storedToken.isEmpty {
            AppLog.probes.debug("Copilot: Using stored token")
            return storedToken
        }

        return nil
    }

    public func isAvailable() async -> Bool {
        let token = getToken()
        guard let username = credentialRepository.get(forKey: CredentialKey.githubUsername),
              let token = token, !token.isEmpty,
              !username.isEmpty else {
            AppLog.probes.debug("Copilot: Not available - missing token or username")
            return false
        }
        return true
    }

    public func probe() async throws -> UsageSnapshot {
        guard let token = getToken(), !token.isEmpty else {
            AppLog.probes.error("Copilot: No GitHub token configured (check token field or env var)")
            throw ProbeError.authenticationRequired
        }

        guard let username = credentialRepository.get(forKey: CredentialKey.githubUsername), !username.isEmpty else {
            AppLog.probes.error("Copilot: No GitHub username configured")
            throw ProbeError.executionFailed("GitHub username not configured")
        }

        AppLog.probes.debug("Copilot: Fetching billing usage for \(username)")

        // Fetch billing usage
        let usageData = try await fetchBillingUsage(username: username, token: token)

        // Parse and create snapshot
        return try parseUsageResponse(usageData, username: username)
    }

    // MARK: - API Calls

    private func fetchBillingUsage(username: String, token: String) async throws -> PremiumRequestUsageResponse {
        // Use premium_request/usage endpoint - specific for Copilot, returns current month
        let urlString = "\(Self.apiBaseURL)/users/\(username)/settings/billing/premium_request/usage"

        guard let url = URL(string: urlString) else {
            throw ProbeError.executionFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = timeout

        let (data, response) = try await networkClient.request(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProbeError.executionFailed("Invalid response")
        }

        AppLog.probes.debug("Copilot API response status: \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            AppLog.probes.error("Copilot: Authentication failed (401)")
            throw ProbeError.authenticationRequired
        case 403:
            AppLog.probes.error("Copilot: Forbidden - check token permissions (403)")
            throw ProbeError.executionFailed("Forbidden - ensure PAT has 'Plan: read' permission")
        case 404:
            AppLog.probes.error("Copilot: User not found or no billing access (404)")
            throw ProbeError.executionFailed("User not found or no billing access")
        default:
            AppLog.probes.error("Copilot: HTTP error \(httpResponse.statusCode)")
            throw ProbeError.executionFailed("HTTP error: \(httpResponse.statusCode)")
        }

        // Log raw response for debugging
        if let rawString = String(data: data, encoding: .utf8) {
            AppLog.probes.debug("Copilot raw response: \(rawString.prefix(1000))")
        }

        do {
            return try JSONDecoder().decode(PremiumRequestUsageResponse.self, from: data)
        } catch {
            AppLog.probes.error("Copilot: Failed to parse response - \(error.localizedDescription)")
            throw ProbeError.parseFailed("Failed to parse billing response: \(error.localizedDescription)")
        }
    }

    // MARK: - Response Parsing

    private func parseUsageResponse(_ response: PremiumRequestUsageResponse, username: String) throws -> UsageSnapshot {
        let items = response.usageItems

        // Filter for Copilot items (product contains 'copilot', case-insensitive)
        let copilotItems = items.filter { item in
            guard let product = item.product?.lowercased() else { return false }
            return product.contains("copilot")
        }

        AppLog.probes.debug("Copilot: Found \(copilotItems.count) Copilot items for \(response.timePeriod.month)/\(response.timePeriod.year)")

        // Log model breakdown
        let modelBreakdown = Dictionary(grouping: copilotItems) { $0.model ?? "Unknown" }
            .mapValues { items in items.reduce(0) { $0 + ($1.grossQuantity ?? 0) } }
        AppLog.probes.debug("Copilot models: \(modelBreakdown)")

        // Calculate totals
        let totalGrossQuantity = copilotItems.reduce(0.0) { $0 + ($1.grossQuantity ?? 0) }
        let totalDiscountQuantity = copilotItems.reduce(0.0) { $0 + ($1.discountQuantity ?? 0) }
        let totalNetQuantity = copilotItems.reduce(0.0) { $0 + ($1.netQuantity ?? 0) }
        let totalNetAmount = copilotItems.reduce(0.0) { $0 + ($1.netAmount ?? 0) }

        AppLog.probes.debug("Copilot: gross=\(Int(totalGrossQuantity)), discount=\(Int(totalDiscountQuantity)), net=\(Int(totalNetQuantity)), amount=\(totalNetAmount)")

        // GitHub Copilot Free tier: ~2000 premium requests/month
        let monthlyLimit: Double = 2000
        let used = totalGrossQuantity
        let remaining = max(0, monthlyLimit - used)
        let percentRemaining = (remaining / monthlyLimit) * 100

        AppLog.probes.debug("Copilot: Used \(Int(used))/\(Int(monthlyLimit)) this month, \(Int(percentRemaining))% remaining")

        // Create quota
        let quota = UsageQuota(
            percentRemaining: percentRemaining,
            quotaType: .session,
            providerId: "copilot",
            resetText: "\(Int(used))/\(Int(monthlyLimit)) requests"
        )

        return UsageSnapshot(
            providerId: "copilot",
            quotas: [quota],
            capturedAt: Date(),
            accountEmail: username
        )
    }
}

// MARK: - API Response Models

/// Response from /users/{username}/settings/billing/premium_request/usage
private struct PremiumRequestUsageResponse: Decodable {
    let timePeriod: TimePeriod
    let user: String
    let usageItems: [PremiumUsageItem]

    struct TimePeriod: Decodable {
        let year: Int
        let month: Int
    }
}

/// Individual premium request usage item.
private struct PremiumUsageItem: Decodable {
    let product: String?
    let sku: String?
    let model: String?
    let unitType: String?
    let pricePerUnit: Double?
    let grossQuantity: Double?
    let grossAmount: Double?
    let discountQuantity: Double?
    let discountAmount: Double?
    let netQuantity: Double?
    let netAmount: Double?
}
