import Foundation
import Domain

/// Claude API-based usage probe that fetches quota data directly from Anthropic's OAuth API.
///
/// This probe uses the user's OAuth credentials (from `~/.claude/.credentials.json` or Keychain)
/// to call the usage API endpoint. It automatically refreshes expired tokens.
///
/// Usage URL: `https://api.anthropic.com/api/oauth/usage`
/// Token Refresh URL: `https://platform.claude.com/v1/oauth/token`
public struct ClaudeAPIUsageProbe: UsageProbe, @unchecked Sendable {
    private let credentialLoader: ClaudeCredentialLoader
    private let networkClient: any NetworkClient
    private let timeout: TimeInterval

    // API endpoints
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let refreshURL = URL(string: "https://platform.claude.com/v1/oauth/token")!

    // OAuth configuration (from Claude Code)
    // client_id being used here is the official client_id being used for Claude Code CLI. It might be changed if Claude Code got updated.
    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    // Only request scopes that are typically granted - do NOT add extra scopes like user:mcp_servers
    private static let scopes = "user:profile user:inference user:sessions:claude_code"

    public init(
        credentialLoader: ClaudeCredentialLoader = ClaudeCredentialLoader(),
        networkClient: any NetworkClient = URLSession.shared,
        timeout: TimeInterval = 15
    ) {
        self.credentialLoader = credentialLoader
        self.networkClient = networkClient
        self.timeout = timeout
    }

    public func isAvailable() async -> Bool {
        credentialLoader.loadCredentials() != nil
    }

    public func probe() async throws -> UsageSnapshot {
        guard var credentials = credentialLoader.loadCredentials() else {
            AppLog.probes.error("Claude API: No credentials found")
            throw ProbeError.authenticationRequired
        }

        // Check if token needs refresh
        if credentialLoader.needsRefresh(credentials.oauth) {
            AppLog.probes.info("Claude API: Token expired or expiring soon, refreshing...")
            do {
                credentials = try await refreshToken(credentials)
            } catch {
                AppLog.probes.error("Claude API: Token refresh failed: \(error.localizedDescription)")
                throw error
            }
        }

        // Fetch usage data
        let usageData: UsageResponse
        do {
            usageData = try await fetchUsage(accessToken: credentials.oauth.accessToken)
        } catch let error as ProbeError where error == .authenticationRequired {
            // Token might have been invalidated, try refreshing once
            AppLog.probes.info("Claude API: Got 401/403, attempting token refresh...")
            do {
                credentials = try await refreshToken(credentials)
                usageData = try await fetchUsage(accessToken: credentials.oauth.accessToken)
            } catch {
                AppLog.probes.error("Claude API: Retry after refresh failed: \(error.localizedDescription)")
                throw error
            }
        }

        return parseUsageResponse(usageData, subscriptionType: credentials.oauth.subscriptionType)
    }

    // MARK: - Token Refresh

    private func refreshToken(_ credentials: ClaudeCredentialResult) async throws -> ClaudeCredentialResult {
        guard let refreshToken = credentials.oauth.refreshToken else {
            AppLog.probes.error("Claude API: No refresh token available")
            throw ProbeError.authenticationRequired
        }

        var request = URLRequest(url: Self.refreshURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID,
            "scope": Self.scopes
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        AppLog.probes.debug("Claude API: Refreshing token...")

        let (data, response) = try await networkClient.request(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProbeError.executionFailed("Invalid response from token refresh")
        }

        // Handle error responses
        if httpResponse.statusCode == 400 || httpResponse.statusCode == 401 {
            // Log raw response for debugging
            if let rawBody = String(data: data, encoding: .utf8) {
                AppLog.probes.debug("Claude API: Token refresh error response: \(rawBody)")
            }

            // Check for specific OAuth errors
            if let errorResponse = try? JSONDecoder().decode(TokenErrorResponse.self, from: data) {
                AppLog.probes.error("Claude API: Token refresh failed - error: \(errorResponse.error ?? "unknown"), description: \(errorResponse.errorDescription ?? "none")")

                if errorResponse.error == "invalid_grant" {
                    AppLog.probes.error("Claude API: Session expired (invalid_grant) - run `claude` to re-authenticate")
                    throw ProbeError.sessionExpired
                }
            }
            AppLog.probes.error("Claude API: Token expired or invalid (HTTP \(httpResponse.statusCode))")
            throw ProbeError.sessionExpired
        }

        guard httpResponse.statusCode >= 200, httpResponse.statusCode < 300 else {
            AppLog.probes.error("Claude API: Token refresh failed with HTTP \(httpResponse.statusCode)")
            throw ProbeError.executionFailed("Token refresh failed: HTTP \(httpResponse.statusCode)")
        }

        // Parse refresh response
        let refreshResponse = try JSONDecoder().decode(TokenRefreshResponse.self, from: data)

        guard let newAccessToken = refreshResponse.accessToken, !newAccessToken.isEmpty else {
            AppLog.probes.error("Claude API: No access token in refresh response")
            throw ProbeError.executionFailed("No access token in refresh response")
        }

        // Update credentials
        var updatedCredentials = credentials
        updatedCredentials.oauth.accessToken = newAccessToken
        if let newRefreshToken = refreshResponse.refreshToken {
            updatedCredentials.oauth.refreshToken = newRefreshToken
        }
        if let expiresIn = refreshResponse.expiresIn {
            updatedCredentials.oauth.expiresAt = Date().timeIntervalSince1970 * 1000 + Double(expiresIn) * 1000
        }

        // Save updated credentials
        credentialLoader.saveCredentials(updatedCredentials)

        AppLog.probes.info("Claude API: Token refreshed successfully")
        return updatedCredentials
    }

    // MARK: - Usage Fetch

    private func fetchUsage(accessToken: String) async throws -> UsageResponse {
        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken.trimmingCharacters(in: .whitespaces))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("ClaudeBar", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = timeout

        AppLog.probes.debug("Claude API: Fetching usage...")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await networkClient.request(request)
        } catch {
            AppLog.probes.error("Claude API: Network error: \(error.localizedDescription)")
            throw ProbeError.executionFailed("Network error: \(error.localizedDescription)")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProbeError.executionFailed("Invalid response")
        }

        AppLog.probes.debug("Claude API: Response status \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200:
            break
        case 401, 403:
            throw ProbeError.authenticationRequired
        default:
            AppLog.probes.error("Claude API: HTTP error \(httpResponse.statusCode)")
            throw ProbeError.executionFailed("HTTP error: \(httpResponse.statusCode)")
        }

        // Log raw response for debugging
        if let rawString = String(data: data, encoding: .utf8) {
            AppLog.probes.debug("Claude API: Raw response: \(rawString.prefix(500))")
        }

        do {
            return try JSONDecoder().decode(UsageResponse.self, from: data)
        } catch {
            AppLog.probes.error("Claude API: Failed to parse response: \(error.localizedDescription)")
            throw ProbeError.parseFailed("Failed to parse usage response: \(error.localizedDescription)")
        }
    }

    // MARK: - Response Parsing

    private func parseUsageResponse(_ response: UsageResponse, subscriptionType: String?) -> UsageSnapshot {
        var quotas: [UsageQuota] = []

        // Parse 5-hour session quota
        if let fiveHour = response.fiveHour, let utilization = fiveHour.utilization {
            let percentRemaining = 100.0 - utilization
            let resetsAt = parseISODate(fiveHour.resetsAt)
            quotas.append(UsageQuota(
                percentRemaining: percentRemaining,
                quotaType: .session,
                providerId: "claude",
                resetsAt: resetsAt,
                resetText: formatResetText(resetsAt)
            ))
        }

        // Parse 7-day weekly quota
        if let sevenDay = response.sevenDay, let utilization = sevenDay.utilization {
            let percentRemaining = 100.0 - utilization
            let resetsAt = parseISODate(sevenDay.resetsAt)
            quotas.append(UsageQuota(
                percentRemaining: percentRemaining,
                quotaType: .weekly,
                providerId: "claude",
                resetsAt: resetsAt,
                resetText: formatResetText(resetsAt)
            ))
        }

        // Parse model-specific quotas
        if let sonnet = response.sevenDaySonnet, let utilization = sonnet.utilization {
            let percentRemaining = 100.0 - utilization
            let resetsAt = parseISODate(sonnet.resetsAt)
            quotas.append(UsageQuota(
                percentRemaining: percentRemaining,
                quotaType: .modelSpecific("sonnet"),
                providerId: "claude",
                resetsAt: resetsAt,
                resetText: formatResetText(resetsAt)
            ))
        }

        if let opus = response.sevenDayOpus, let utilization = opus.utilization {
            let percentRemaining = 100.0 - utilization
            let resetsAt = parseISODate(opus.resetsAt)
            quotas.append(UsageQuota(
                percentRemaining: percentRemaining,
                quotaType: .modelSpecific("opus"),
                providerId: "claude",
                resetsAt: resetsAt,
                resetText: formatResetText(resetsAt)
            ))
        }

        // Parse extra usage
        var costUsage: CostUsage?
        if let extra = response.extraUsage, extra.isEnabled == true {
            if let used = extra.usedCredits {
                costUsage = CostUsage(
                    totalCost: Decimal(used),
                    budget: extra.monthlyLimit.map { Decimal($0) },
                    apiDuration: 0,
                    providerId: "claude",
                    capturedAt: Date(),
                    resetsAt: nil,
                    resetText: nil
                )
            }
        }

        // Determine account tier from subscription type
        let accountTier = parseAccountTier(subscriptionType)

        AppLog.probes.info("Claude API: Parsed \(quotas.count) quotas, tier=\(accountTier?.badgeText ?? "unknown")")

        return UsageSnapshot(
            providerId: "claude",
            quotas: quotas,
            capturedAt: Date(),
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: nil,
            accountTier: accountTier,
            costUsage: costUsage
        )
    }

    private func parseISODate(_ isoString: String?) -> Date? {
        guard let isoString else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: isoString) {
            return date
        }

        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: isoString)
    }

    private func formatResetText(_ date: Date?) -> String? {
        guard let date else { return nil }

        let now = Date()
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return nil }

        let hours = Int(seconds / 3600)
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)

        if hours > 0 {
            return "Resets in \(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "Resets in \(minutes)m"
        } else {
            return "Resets soon"
        }
    }

    private func parseAccountTier(_ subscriptionType: String?) -> AccountTier? {
        guard let subscriptionType else { return nil }

        switch subscriptionType.lowercased() {
        case "claude_max", "max":
            return .claudeMax
        case "claude_pro", "pro":
            return .claudePro
        case "api", "claude_api":
            return .claudeApi
        default:
            return .custom(subscriptionType)
        }
    }
}

// MARK: - Response Models

private struct UsageResponse: Decodable {
    let fiveHour: UsageQuotaData?
    let sevenDay: UsageQuotaData?
    let sevenDaySonnet: UsageQuotaData?
    let sevenDayOpus: UsageQuotaData?
    let extraUsage: ExtraUsageData?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayOpus = "seven_day_opus"
        case extraUsage = "extra_usage"
    }
}

private struct UsageQuotaData: Decodable {
    let utilization: Double?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

private struct ExtraUsageData: Decodable {
    let isEnabled: Bool?
    let usedCredits: Double?
    let monthlyLimit: Double?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case usedCredits = "used_credits"
        case monthlyLimit = "monthly_limit"
    }
}

private struct TokenRefreshResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct TokenErrorResponse: Decodable {
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}
