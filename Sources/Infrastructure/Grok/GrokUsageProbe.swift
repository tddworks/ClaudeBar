import Foundation
import Domain

/// Grok Build (xAI) usage probe that fetches credit usage from the same
/// billing endpoint the `grok` CLI uses.
///
/// Uses the OAuth credentials from `~/.grok/auth.json`, refreshing expired
/// tokens against the OIDC issuer recorded alongside them.
///
/// Usage URL: `https://cli-chat-proxy.grok.com/v1/billing?format=credits`
/// Token Refresh URL: `{oidc_issuer}/oauth2/token` (defaults to `https://auth.x.ai`)
public struct GrokUsageProbe: UsageProbe, @unchecked Sendable {
    private let credentialLoader: GrokCredentialLoader
    private let networkClient: any NetworkClient
    private let timeout: TimeInterval

    private static let billingURL = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!
    private static let defaultIssuer = "https://auth.x.ai"
    private static let reloginHint = "Run `grok login` in terminal to log in again."

    public init(
        credentialLoader: GrokCredentialLoader = GrokCredentialLoader(),
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
            AppLog.probes.error("Grok: No credentials found")
            throw ProbeError.authenticationRequired
        }

        // Refresh proactively when the stored token is expired or about to be
        if credentialLoader.needsRefresh(expiresAt: credentials.expiresAt), credentials.refreshToken != nil {
            AppLog.probes.info("Grok: Token expired or expiring, refreshing...")
            do {
                credentials = try await refreshToken(credentials)
            } catch let error as ProbeError where error == .sessionExpired() {
                throw error
            } catch {
                AppLog.probes.warning("Grok: Proactive refresh failed: \(error.localizedDescription), trying with existing token")
            }
        }

        let data: Data
        do {
            data = try await fetchBilling(accessToken: credentials.accessToken)
        } catch let error as ProbeError where error == .authenticationRequired {
            // Token was rejected — refresh once and retry
            AppLog.probes.info("Grok: Got 401, attempting token refresh...")
            credentials = try await refreshToken(credentials)
            do {
                data = try await fetchBilling(accessToken: credentials.accessToken)
            } catch let error as ProbeError where error == .authenticationRequired {
                throw ProbeError.sessionExpired(hint: Self.reloginHint)
            }
        }

        return try Self.parseResponse(data, providerId: "grok", accountEmail: credentials.email)
    }

    // MARK: - Token Refresh

    private func refreshToken(_ credentials: GrokCredentialResult) async throws -> GrokCredentialResult {
        guard let refreshToken = credentials.refreshToken else {
            AppLog.probes.error("Grok: No refresh token available")
            throw ProbeError.sessionExpired(hint: Self.reloginHint)
        }

        let issuer = credentials.oidcIssuer ?? Self.defaultIssuer
        guard let refreshURL = URL(string: issuer.hasSuffix("/") ? issuer + "oauth2/token" : issuer + "/oauth2/token") else {
            throw ProbeError.executionFailed("Invalid OIDC issuer: \(issuer)")
        }

        var request = URLRequest(url: refreshURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        var bodyString = "grant_type=refresh_token"
            + "&refresh_token=" + (refreshToken.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? refreshToken)
        if let clientId = credentials.oidcClientId {
            bodyString += "&client_id=" + (clientId.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? clientId)
        }
        request.httpBody = bodyString.data(using: .utf8)

        AppLog.probes.debug("Grok: Refreshing token...")

        let (data, response) = try await networkClient.request(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProbeError.executionFailed("Invalid response from token refresh")
        }

        if httpResponse.statusCode == 400 || httpResponse.statusCode == 401 {
            // Log only the OAuth error code — the raw body may carry sensitive data
            let errorObject = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let errorCode = (errorObject?["error"] as? String) ?? "unknown"
            AppLog.probes.error("Grok: Token refresh rejected (HTTP \(httpResponse.statusCode), error: \(errorCode))")
            throw ProbeError.sessionExpired(hint: Self.reloginHint)
        }

        guard httpResponse.statusCode >= 200, httpResponse.statusCode < 300 else {
            AppLog.probes.error("Grok: Token refresh failed with HTTP \(httpResponse.statusCode)")
            throw ProbeError.executionFailed("Token refresh failed: HTTP \(httpResponse.statusCode)")
        }

        guard let responseDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccessToken = responseDict["access_token"] as? String,
              !newAccessToken.isEmpty else {
            AppLog.probes.error("Grok: No access token in refresh response")
            throw ProbeError.executionFailed("No access token in refresh response")
        }

        var updatedCredentials = credentials
        updatedCredentials.accessToken = newAccessToken
        if let newRefreshToken = responseDict["refresh_token"] as? String, !newRefreshToken.isEmpty {
            updatedCredentials.refreshToken = newRefreshToken
        }
        if let expiresIn = responseDict["expires_in"] as? Double {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            updatedCredentials.expiresAt = formatter.string(from: Date().addingTimeInterval(expiresIn))
        }

        credentialLoader.saveCredentials(updatedCredentials)

        AppLog.probes.info("Grok: Token refreshed successfully")
        return updatedCredentials
    }

    // MARK: - Billing Fetch

    private func fetchBilling(accessToken: String) async throws -> Data {
        var request = URLRequest(url: Self.billingURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("build", forHTTPHeaderField: "x-grok-client-mode")
        request.timeoutInterval = timeout

        AppLog.probes.debug("Grok: Fetching billing data...")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await networkClient.request(request)
        } catch {
            AppLog.probes.error("Grok: Network error: \(error.localizedDescription)")
            throw ProbeError.executionFailed("Network error: \(error.localizedDescription)")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProbeError.executionFailed("Invalid response")
        }

        AppLog.probes.debug("Grok: Response status \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200:
            return data
        case 401, 403:
            throw ProbeError.authenticationRequired
        default:
            AppLog.probes.error("Grok: HTTP error \(httpResponse.statusCode)")
            throw ProbeError.executionFailed("HTTP error: \(httpResponse.statusCode)")
        }
    }

    // MARK: - Response Parsing

    /// Parses the billing credits payload into a usage snapshot.
    ///
    /// Response shape (from the `grok` CLI's billing extension):
    /// ```json
    /// {
    ///   "config": {
    ///     "currentPeriod": {"type": "USAGE_PERIOD_TYPE_WEEKLY", "start": "...", "end": "..."},
    ///     "creditUsagePercent": 96.0,
    ///     "onDemandCap": {"val": 0},
    ///     "onDemandUsed": {"val": 0},
    ///     "productUsage": [{"product": "GrokBuild", "usagePercent": 84.0}, ...]
    ///   }
    /// }
    /// ```
    static func parseResponse(
        _ data: Data,
        providerId: String,
        accountEmail: String? = nil,
        now: Date = Date()
    ) throws -> UsageSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProbeError.parseFailed("Failed to parse billing response as JSON")
        }

        let config = (root["config"] as? [String: Any]) ?? root

        let period = config["currentPeriod"] as? [String: Any]
        let periodEnd = GrokCredentialLoader.parseDate(period?["end"] as? String)
        let periodStart = GrokCredentialLoader.parseDate(period?["start"] as? String)
        let windowDuration: TimeInterval? = {
            guard let periodStart, let periodEnd else { return nil }
            let duration = periodEnd.timeIntervalSince(periodStart)
            return duration > 0 ? duration : nil
        }()
        let periodQuotaType = quotaType(forPeriodType: period?["type"] as? String)
        let resetText = formatResetText(periodEnd, now: now)

        var quotas: [UsageQuota] = []

        // Overall credit usage for the current period
        if let creditUsagePercent = doubleValue(config["creditUsagePercent"]) {
            quotas.append(UsageQuota(
                percentRemaining: max(-100, 100 - creditUsagePercent),
                quotaType: periodQuotaType,
                providerId: providerId,
                resetsAt: periodEnd,
                resetText: resetText,
                windowDuration: windowDuration
            ))
        }

        // Per-product usage (Grok Build, Grok Imagine, Grok Voice, ...)
        for product in (config["productUsage"] as? [[String: Any]]) ?? [] {
            guard let name = product["product"] as? String,
                  let usagePercent = doubleValue(product["usagePercent"]) else {
                continue
            }
            quotas.append(UsageQuota(
                percentRemaining: max(-100, 100 - usagePercent),
                quotaType: .modelSpecific(productDisplayName(name)),
                providerId: providerId,
                resetsAt: periodEnd,
                resetText: resetText,
                windowDuration: windowDuration
            ))
        }

        // On-demand overflow spend, only meaningful once a cap is configured
        if let cap = wrappedValue(config["onDemandCap"]), cap > 0 {
            let used = wrappedValue(config["onDemandUsed"]) ?? 0
            quotas.append(UsageQuota(
                percentRemaining: max(-100, 100 - used / cap * 100),
                quotaType: .timeLimit("On-Demand"),
                providerId: providerId,
                resetsAt: periodEnd,
                resetText: resetText,
                windowDuration: windowDuration
            ))
        }

        // Fallback: billing returns 200 with a valid period but no usage
        // percentages (fresh period with zero usage, or an unmetered plan).
        // Without this the card renders an empty grid. Treat "no usage
        // reported" as 100% remaining for the current window.
        if quotas.isEmpty, periodStart != nil || periodEnd != nil {
            AppLog.probes.info("Grok: No usage percentages in billing response, showing full remaining for current period")
            quotas.append(UsageQuota(
                percentRemaining: 100,
                quotaType: periodQuotaType,
                providerId: providerId,
                resetsAt: periodEnd,
                resetText: resetText,
                windowDuration: windowDuration
            ))
        }

        AppLog.probes.info("Grok: Parsed \(quotas.count) quotas")

        return UsageSnapshot(
            providerId: providerId,
            quotas: quotas,
            capturedAt: now,
            accountEmail: accountEmail
        )
    }

    // MARK: - Parsing Helpers

    /// Maps xAI's usage period type onto the closest quota window.
    static func quotaType(forPeriodType type: String?) -> QuotaType {
        guard let type else { return .weekly }
        if type.contains("MONTHLY") { return .timeLimit("Monthly") }
        if type.contains("DAILY") { return .timeLimit("Daily") }
        return .weekly
    }

    /// "GrokBuild" → "Build", "GrokImagine" → "Imagine". Unknown products
    /// keep their name with camelCase split into words.
    static func productDisplayName(_ raw: String) -> String {
        var name = raw
        if name.hasPrefix("Grok"), name.count > "Grok".count {
            name = String(name.dropFirst("Grok".count))
        }
        var result = ""
        for character in name {
            if character.isUppercase, let last = result.last, last.isLowercase {
                result.append(" ")
            }
            result.append(character)
        }
        return result
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        return nil
    }

    /// Unwraps xAI's `{"val": N}` amount wrapper.
    private static func wrappedValue(_ value: Any?) -> Double? {
        guard let wrapper = value as? [String: Any] else { return nil }
        return doubleValue(wrapper["val"])
    }

    private static func formatResetText(_ date: Date?, now: Date) -> String? {
        guard let date else { return nil }
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return nil }

        let days = Int(seconds / 86400)
        let hours = Int((seconds.truncatingRemainder(dividingBy: 86400)) / 3600)
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)

        if days > 0 {
            return "Resets in \(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            return "Resets in \(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "Resets in \(minutes)m"
        } else {
            return "Resets soon"
        }
    }
}
