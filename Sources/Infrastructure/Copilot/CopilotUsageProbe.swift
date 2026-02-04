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
    private let settingsRepository: any CopilotSettingsRepository
    private let timeout: TimeInterval

    private static let apiBaseURL = "https://api.github.com"
    private static let apiVersion = "2022-11-28"

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
                AppLog.probes.debug("Copilot: Using token from env var '\(envVarName)'")
                return envValue
            }
        }

        // Fall back to stored token
        if let storedToken = settingsRepository.getGithubToken(), !storedToken.isEmpty {
            AppLog.probes.debug("Copilot: Using stored token")
            return storedToken
        }

        return nil
    }

    public func isAvailable() async -> Bool {
        let token = getToken()
        guard let username = settingsRepository.getGithubUsername(),
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

        guard let username = settingsRepository.getGithubUsername(), !username.isEmpty else {
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

        // Check if usage period changed (new billing month)
        let currentMonth = response.timePeriod.month
        let currentYear = response.timePeriod.year
        let lastMonth = settingsRepository.copilotLastUsagePeriodMonth()
        let lastYear = settingsRepository.copilotLastUsagePeriodYear()
        
        if let lastMonth, let lastYear, (currentMonth != lastMonth || currentYear != lastYear) {
            AppLog.probes.info("Copilot: Usage period changed from \(lastMonth)/\(lastYear) to \(currentMonth)/\(currentYear) - clearing manual entry")
            settingsRepository.setCopilotManualUsageValue(nil)
        }
        
        // Update stored period
        settingsRepository.setCopilotLastUsagePeriod(month: currentMonth, year: currentYear)

        // Detect if API returned empty Copilot data (common for org-based Copilot Business)
        // Note: We check copilotItems specifically to handle cases where API returns
        // other product usage (e.g., GitHub Actions) but no Copilot usage data.
        // We set the flag but don't auto-enable manual override to avoid
        // conflating "zero usage" with "API can't report usage"
        let apiReturnedEmpty = copilotItems.isEmpty
        if apiReturnedEmpty {
            AppLog.probes.info("Copilot: API returned no Copilot usage items (could be zero usage or org-based subscription)")
            settingsRepository.setCopilotApiReturnedEmpty(true)
        } else {
            // Clear the flag if we got Copilot data
            settingsRepository.setCopilotApiReturnedEmpty(false)
        }

        // Log model breakdown
        let modelBreakdown = Dictionary(grouping: copilotItems) { $0.model ?? "Unknown" }
            .mapValues { items in items.reduce(0) { $0 + ($1.grossQuantity ?? 0) } }
        if !copilotItems.isEmpty {
            AppLog.probes.debug("Copilot models: \(modelBreakdown)")
        }

        // Calculate totals from API
        let totalGrossQuantity = copilotItems.reduce(0.0) { $0 + ($1.grossQuantity ?? 0) }
        let totalDiscountQuantity = copilotItems.reduce(0.0) { $0 + ($1.discountQuantity ?? 0) }
        let totalNetQuantity = copilotItems.reduce(0.0) { $0 + ($1.netQuantity ?? 0) }
        let totalNetAmount = copilotItems.reduce(0.0) { $0 + ($1.netAmount ?? 0) }

        if !copilotItems.isEmpty {
            AppLog.probes.debug("Copilot: gross=\(Int(totalGrossQuantity)), discount=\(Int(totalDiscountQuantity)), net=\(Int(totalNetQuantity)), amount=\(totalNetAmount)")
        }

        // Use configured monthly limit or default to 50 (Free/Pro tier premium requests)
        // Note: 2000 is code completions limit, not premium requests limit
        var monthlyLimit: Double = Double(settingsRepository.copilotMonthlyLimit() ?? 50)
        
        // Guard against division by zero (ensure monthlyLimit is positive)
        if monthlyLimit <= 0 {
            AppLog.probes.warning("Copilot: Invalid monthly limit (\(Int(monthlyLimit))), using default 50")
            monthlyLimit = 50
        }
        
        // Determine usage: manual override or API data
        let manualOverrideEnabled = settingsRepository.copilotManualOverrideEnabled()
        let used: Double
        let isManual: Bool
        
        if manualOverrideEnabled, let manualValue = settingsRepository.copilotManualUsageValue() {
            // Manual override is enabled AND value is set - use manual value
            let isPercent = settingsRepository.copilotManualUsageIsPercent()
            
            if isPercent {
                // Value is a percentage of quota used (e.g., 198 means 198% used)
                let percentUsed = manualValue
                used = (percentUsed / 100.0) * monthlyLimit
                AppLog.probes.info("Copilot: Using manual override - \(Int(percentUsed))% used = \(Int(used))/\(Int(monthlyLimit))")
            } else {
                // Value is request count
                used = manualValue
                AppLog.probes.info("Copilot: Using manual override - \(Int(used))/\(Int(monthlyLimit))")
            }
            
            isManual = true
        } else if manualOverrideEnabled && apiReturnedEmpty {
            // Manual override enabled but no value set, and API returned no data
            AppLog.probes.warning("Copilot: Manual override enabled but no value set")
            throw ProbeError.executionFailed("Manual usage override enabled but no value entered. Please enter your current usage from GitHub settings.")
        } else {
            // Use API data (or zero if no API data but manual override not enabled)
            used = totalGrossQuantity
            isManual = false
        }
        
        // Allow negative percentages to show over-quota usage
        let remaining = monthlyLimit - used
        let percentRemaining = (remaining / monthlyLimit) * 100

        AppLog.probes.debug("Copilot: Used \(Int(used))/\(Int(monthlyLimit)) this month, \(Int(percentRemaining))% remaining")

        // Create quota with manual indicator
        let resetText = isManual 
            ? "\(Int(used))/\(Int(monthlyLimit)) requests (manual)"
            : "\(Int(used))/\(Int(monthlyLimit)) requests"
        
        let quota = UsageQuota(
            percentRemaining: percentRemaining,
            quotaType: .session,
            providerId: "copilot",
            resetText: resetText
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
