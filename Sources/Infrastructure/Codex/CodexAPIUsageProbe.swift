import Foundation
import Domain

/// Codex API-based usage probe that fetches quota data directly from the ChatGPT backend API.
///
/// This probe uses the user's OAuth credentials (from `~/.codex/auth.json`)
/// to call the usage API endpoint. It automatically refreshes expired tokens.
///
/// Usage URL: `https://chatgpt.com/backend-api/wham/usage`
/// Token Refresh URL: `https://auth.openai.com/oauth/token`
public struct CodexAPIUsageProbe: UsageProbe, @unchecked Sendable {
    private let credentialLoader: CodexCredentialLoader
    private let networkClient: any NetworkClient
    private let timeout: TimeInterval

    // API endpoints
    private static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private static let refreshURL = URL(string: "https://auth.openai.com/oauth/token")!

    // OAuth configuration (from Codex JS reference)
    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    public init(
        credentialLoader: CodexCredentialLoader = CodexCredentialLoader(),
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
            AppLog.probes.error("Codex API: No credentials found")
            throw ProbeError.authenticationRequired
        }

        // Check if token needs refresh (based on last_refresh age)
        if credentialLoader.needsRefresh(lastRefresh: credentials.lastRefresh) {
            AppLog.probes.info("Codex API: Token needs refresh (last_refresh > 8 days)")
            do {
                credentials = try await refreshToken(credentials)
            } catch {
                AppLog.probes.warning("Codex API: Proactive refresh failed: \(error.localizedDescription), trying with existing token")
                // Don't throw here - try the existing token first
                if case ProbeError.sessionExpired = error {
                    throw error
                }
            }
        }

        // Fetch usage data
        let (data, httpResponse): (Data, HTTPURLResponse)
        do {
            (data, httpResponse) = try await fetchUsage(
                accessToken: credentials.accessToken,
                accountId: credentials.accountId
            )
        } catch let error as ProbeError where error == .authenticationRequired {
            // Token might have been invalidated, try refreshing once
            AppLog.probes.info("Codex API: Got 401, attempting token refresh...")
            do {
                credentials = try await refreshToken(credentials)
                (data, httpResponse) = try await fetchUsage(
                    accessToken: credentials.accessToken,
                    accountId: credentials.accountId
                )
            } catch {
                AppLog.probes.error("Codex API: Retry after refresh failed: \(error.localizedDescription)")
                throw error
            }
        }

        return try parseUsageResponse(data: data, httpResponse: httpResponse)
    }

    // MARK: - Token Refresh

    private func refreshToken(_ credentials: CodexCredentialResult) async throws -> CodexCredentialResult {
        guard let refreshToken = credentials.refreshToken else {
            AppLog.probes.error("Codex API: No refresh token available")
            throw ProbeError.authenticationRequired
        }

        var request = URLRequest(url: Self.refreshURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        // Form-urlencoded body (matching Codex JS reference)
        let bodyString = "grant_type=refresh_token"
            + "&client_id=" + Self.clientID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
            + "&refresh_token=" + refreshToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        request.httpBody = bodyString.data(using: .utf8)

        AppLog.probes.debug("Codex API: Refreshing token...")

        let (data, response) = try await networkClient.request(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProbeError.executionFailed("Invalid response from token refresh")
        }

        // Handle error responses
        if httpResponse.statusCode == 400 || httpResponse.statusCode == 401 {
            if let rawBody = String(data: data, encoding: .utf8) {
                AppLog.probes.debug("Codex API: Token refresh error response: \(rawBody)")
            }

            // Check for specific error codes
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let code = extractErrorCode(from: errorData)

                if code == "refresh_token_expired" || code == "refresh_token_reused" || code == "refresh_token_invalidated" {
                    AppLog.probes.error("Codex API: Session expired (\(code ?? "unknown")) - run `codex` to re-authenticate")
                    throw ProbeError.sessionExpired
                }
            }

            AppLog.probes.error("Codex API: Token expired or invalid (HTTP \(httpResponse.statusCode))")
            throw ProbeError.sessionExpired
        }

        guard httpResponse.statusCode >= 200, httpResponse.statusCode < 300 else {
            AppLog.probes.error("Codex API: Token refresh failed with HTTP \(httpResponse.statusCode)")
            throw ProbeError.executionFailed("Token refresh failed: HTTP \(httpResponse.statusCode)")
        }

        // Parse refresh response
        guard let responseDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccessToken = responseDict["access_token"] as? String,
              !newAccessToken.isEmpty else {
            AppLog.probes.error("Codex API: No access token in refresh response")
            throw ProbeError.executionFailed("No access token in refresh response")
        }

        // Update credentials
        var updatedCredentials = credentials
        updatedCredentials.accessToken = newAccessToken
        if let newRefreshToken = responseDict["refresh_token"] as? String {
            updatedCredentials.refreshToken = newRefreshToken
        }
        if let idToken = responseDict["id_token"] as? String {
            var fullData = updatedCredentials.fullData
            if var tokens = fullData["tokens"] as? [String: Any] {
                tokens["id_token"] = idToken
                fullData["tokens"] = tokens
                updatedCredentials.fullData = fullData
            }
        }
        updatedCredentials.lastRefresh = ISO8601DateFormatter().string(from: Date())

        // Save updated credentials
        credentialLoader.saveCredentials(updatedCredentials)

        AppLog.probes.info("Codex API: Token refreshed successfully")
        return updatedCredentials
    }

    // MARK: - Usage Fetch

    private func fetchUsage(accessToken: String, accountId: String?) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("OpenUsage", forHTTPHeaderField: "User-Agent")
        if let accountId {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        request.timeoutInterval = timeout

        AppLog.probes.debug("Codex API: Fetching usage...")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await networkClient.request(request)
        } catch {
            AppLog.probes.error("Codex API: Network error: \(error.localizedDescription)")
            throw ProbeError.executionFailed("Network error: \(error.localizedDescription)")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProbeError.executionFailed("Invalid response")
        }

        AppLog.probes.debug("Codex API: Response status \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200:
            break
        case 401, 403:
            throw ProbeError.authenticationRequired
        default:
            AppLog.probes.error("Codex API: HTTP error \(httpResponse.statusCode)")
            throw ProbeError.executionFailed("HTTP error: \(httpResponse.statusCode)")
        }

        return (data, httpResponse)
    }

    // MARK: - Response Parsing

    private func parseUsageResponse(data: Data, httpResponse: HTTPURLResponse) throws -> UsageSnapshot {
        // Log raw response for debugging
        if let rawString = String(data: data, encoding: .utf8) {
            AppLog.probes.debug("Codex API: Raw response: \(rawString.prefix(500))")
        }

        guard let responseDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProbeError.parseFailed("Failed to parse usage response as JSON")
        }

        var quotas: [UsageQuota] = []
        let nowSeconds = Date().timeIntervalSince1970

        let rateLimit = responseDict["rate_limit"] as? [String: Any]
        let primaryWindow = rateLimit?["primary_window"] as? [String: Any]
        let secondaryWindow = rateLimit?["secondary_window"] as? [String: Any]

        // Try headers first (preferred), then fall back to body
        let headerPrimary = readHeaderDouble(httpResponse, key: "x-codex-primary-used-percent")
        let headerSecondary = readHeaderDouble(httpResponse, key: "x-codex-secondary-used-percent")

        if let primary = headerPrimary {
            quotas.append(UsageQuota(
                percentRemaining: max(0, 100 - primary),
                quotaType: .session,
                providerId: "codex",
                resetsAt: resetsAtDate(nowSeconds: nowSeconds, window: primaryWindow),
                resetText: formatResetText(resetsAtDate(nowSeconds: nowSeconds, window: primaryWindow))
            ))
        }
        if let secondary = headerSecondary {
            quotas.append(UsageQuota(
                percentRemaining: max(0, 100 - secondary),
                quotaType: .weekly,
                providerId: "codex",
                resetsAt: resetsAtDate(nowSeconds: nowSeconds, window: secondaryWindow),
                resetText: formatResetText(resetsAtDate(nowSeconds: nowSeconds, window: secondaryWindow))
            ))
        }

        // Fall back to body if headers not present
        if quotas.isEmpty {
            if let usedPercent = primaryWindow?["used_percent"] as? Double {
                quotas.append(UsageQuota(
                    percentRemaining: max(0, 100 - usedPercent),
                    quotaType: .session,
                    providerId: "codex",
                    resetsAt: resetsAtDate(nowSeconds: nowSeconds, window: primaryWindow),
                    resetText: formatResetText(resetsAtDate(nowSeconds: nowSeconds, window: primaryWindow))
                ))
            }
            if let usedPercent = secondaryWindow?["used_percent"] as? Double {
                quotas.append(UsageQuota(
                    percentRemaining: max(0, 100 - usedPercent),
                    quotaType: .weekly,
                    providerId: "codex",
                    resetsAt: resetsAtDate(nowSeconds: nowSeconds, window: secondaryWindow),
                    resetText: formatResetText(resetsAtDate(nowSeconds: nowSeconds, window: secondaryWindow))
                ))
            }
        }

        // Parse credits
        var costUsage: CostUsage?
        let creditsHeader = readHeaderDouble(httpResponse, key: "x-codex-credits-balance")
        let creditsBody = (responseDict["credits"] as? [String: Any])?["balance"] as? Double
        if let creditsRemaining = creditsHeader ?? creditsBody {
            let limit: Decimal = 1000
            let used = max(0, min(limit, limit - Decimal(creditsRemaining)))
            costUsage = CostUsage(
                totalCost: used,
                budget: limit,
                apiDuration: 0,
                providerId: "codex",
                capturedAt: Date(),
                resetsAt: nil,
                resetText: nil
            )
        }

        // Parse plan type
        var accountTier: AccountTier?
        if let planType = responseDict["plan_type"] as? String, !planType.isEmpty {
            accountTier = parsePlanType(planType)
        }

        AppLog.probes.info("Codex API: Parsed \(quotas.count) quotas, tier=\(accountTier?.badgeText ?? "unknown")")

        return UsageSnapshot(
            providerId: "codex",
            quotas: quotas,
            capturedAt: Date(),
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: nil,
            accountTier: accountTier,
            costUsage: costUsage
        )
    }

    // MARK: - Helpers

    private func readHeaderDouble(_ response: HTTPURLResponse, key: String) -> Double? {
        guard let value = response.value(forHTTPHeaderField: key) else { return nil }
        let n = Double(value)
        return n?.isFinite == true ? n : nil
    }

    private func resetsAtDate(nowSeconds: TimeInterval, window: [String: Any]?) -> Date? {
        guard let window else { return nil }
        if let resetAt = window["reset_at"] as? Double {
            return Date(timeIntervalSince1970: resetAt)
        }
        if let resetAfterSeconds = window["reset_after_seconds"] as? Double {
            return Date(timeIntervalSince1970: nowSeconds + resetAfterSeconds)
        }
        return nil
    }

    private func formatResetText(_ date: Date?) -> String? {
        guard let date else { return nil }
        let seconds = date.timeIntervalSinceNow
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

    private func parsePlanType(_ planType: String) -> AccountTier {
        switch planType.lowercased() {
        case "plus":
            return .custom("PLUS")
        case "pro":
            return .custom("PRO")
        case "free":
            return .custom("FREE")
        default:
            return .custom(planType.uppercased())
        }
    }

    private func extractErrorCode(from errorData: [String: Any]) -> String? {
        // Try nested: { "error": { "code": "..." } }
        if let errorObj = errorData["error"] as? [String: Any],
           let code = errorObj["code"] as? String {
            return code
        }
        // Try flat: { "error": "..." }
        if let errorStr = errorData["error"] as? String {
            return errorStr
        }
        // Try top-level: { "code": "..." }
        if let code = errorData["code"] as? String {
            return code
        }
        return nil
    }
}
