import Foundation
import Domain

/// Thread-safe TTL cache for a successful `UsageSnapshot`. Quota numbers
/// move on multi-hour timescales (5h session, 7d weekly), so returning the
/// most recent successful snapshot for a short window costs nothing in
/// freshness and dramatically reduces requests against the rate-limited
/// usage endpoint.
private final class SnapshotCache: @unchecked Sendable {
    private var cached: UsageSnapshot?
    private var cachedAt: Date?
    private let ttl: TimeInterval
    private let lock = NSLock()

    /// Creates a snapshot cache with the given maximum lifetime for a cached
    /// entry. A `ttl` of `0` effectively disables caching (every `get` misses).
    init(ttl: TimeInterval) {
        self.ttl = ttl
    }

    /// Returns the cached snapshot if it was stored within `ttl` of `now`;
    /// otherwise evicts the stale entry and returns `nil` so the caller knows
    /// to re-fetch.
    func get(now: Date = Date()) -> UsageSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        guard let cached, let cachedAt else { return nil }
        // Inclusive comparison so `ttl == 0` is always immediately stale.
        // With `>`, a 0-TTL cache would still hit within the same instant.
        if now.timeIntervalSince(cachedAt) >= ttl {
            self.cached = nil
            self.cachedAt = nil
            return nil
        }
        return cached
    }

    /// Stores a fresh snapshot and stamps it with `now`, replacing any prior
    /// entry. The next `get` call within `ttl` of `now` will hit this entry.
    func set(_ snapshot: UsageSnapshot, now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        self.cached = snapshot
        self.cachedAt = now
    }
}

/// Thread-safe holder for an active rate-limit window. When the API returns
/// HTTP 429, the probe stores `retryAt` here so subsequent calls short-circuit
/// without re-hitting the endpoint until the window has elapsed.
private final class RateLimitState: @unchecked Sendable {
    private var retryAt: Date?
    private let lock = NSLock()

    /// Returns `retryAt` only if it is still in the future; otherwise clears
    /// it and returns nil so the next probe is allowed through.
    func activeRetryAt(now: Date = Date()) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        guard let retryAt else { return nil }
        if retryAt <= now {
            self.retryAt = nil
            return nil
        }
        return retryAt
    }

    /// Records a new rate-limit window expiring at `retryAt`. Subsequent
    /// `activeRetryAt` calls return this value until it falls into the past.
    func set(retryAt: Date) {
        lock.lock()
        defer { lock.unlock() }
        self.retryAt = retryAt
    }
}

/// Thread-safe in-memory cache for Claude OAuth credentials with TTL.
/// Avoids repeated Keychain/CLI lookups on every probe cycle while ensuring
/// external credential changes (e.g. CLI re-login) are picked up.
private final class CredentialCache: @unchecked Sendable {
    private var cached: ClaudeCredentialResult?
    private var cachedAt: Date?
    private let lock = NSLock()

    /// Cache TTL: 5 minutes. Forces reload from file to detect external changes.
    /// 缓存生存时间：5分钟，确保能感知 CLI 等外部凭证变更
    static let ttl: TimeInterval = 5 * 60

    func get() -> ClaudeCredentialResult? {
        lock.lock()
        defer { lock.unlock() }
        // Invalidate if TTL expired
        // TTL 过期时自动失效，下次从文件重新加载
        if let cachedAt, Date().timeIntervalSince(cachedAt) > Self.ttl {
            cached = nil
            self.cachedAt = nil
            return nil
        }
        return cached
    }

    func set(_ credentials: ClaudeCredentialResult) {
        lock.lock()
        defer { lock.unlock() }
        cached = credentials
        cachedAt = Date()
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        cached = nil
        cachedAt = nil
    }
}

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
    private let cache = CredentialCache()
    private let rateLimit = RateLimitState()
    private let snapshotCache: SnapshotCache

    /// Fallback retry window applied when the API returns 429 without a
    /// usable `Retry-After` header. Five minutes is conservative enough to
    /// stop hammering a throttled endpoint while still picking back up
    /// reasonably quickly once the window opens.
    static let defaultRetryAfter: TimeInterval = 5 * 60

    /// Default TTL for the in-memory snapshot cache. Anthropic's
    /// /api/oauth/usage throttle has been observed handing out 1-hour
    /// Retry-After windows in response to even one call after a quiet
    /// period (see deferred memory + anthropics/claude-code#30930), so
    /// we err on the conservative side. 15 minutes drops the 60s monitor
    /// cadence to ~4 calls/hour — well under any reasonable threshold —
    /// while still keeping the displayed quotas fresh enough that a user
    /// glancing at the menu bar isn't looking at hour-old data.
    public static let defaultSnapshotCacheTTL: TimeInterval = 15 * 60

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
        timeout: TimeInterval = 15,
        snapshotCacheTTL: TimeInterval = Self.defaultSnapshotCacheTTL
    ) {
        self.credentialLoader = credentialLoader
        self.networkClient = networkClient
        self.timeout = timeout
        self.snapshotCache = SnapshotCache(ttl: snapshotCacheTTL)
    }

    public func isAvailable() async -> Bool {
        if cache.get() != nil { return true }
        return credentialLoader.loadCredentials() != nil
    }

    public func probe() async throws -> UsageSnapshot {
        // Serve a fresh cached snapshot before doing anything else. This is
        // the dominant code path during normal monitor polling and means
        // we make ~1 actual HTTP call per cache TTL instead of one per
        // monitor tick — well under Anthropic's per-token throttle.
        if let cached = snapshotCache.get() {
            return cached
        }

        // Honor an active rate-limit window before doing any work so we stop
        // hammering the endpoint while Anthropic is throttling us.
        if let retryAt = rateLimit.activeRetryAt() {
            AppLog.probes.info("Claude API: Skipping probe — rate-limited until \(retryAt)")
            throw ProbeError.rateLimited(retryAt: retryAt)
        }

        // Check cache first, fall back to loading from file/keychain
        // Only update cache when loading from file (not from cache hit) to preserve TTL
        // 仅在从文件加载时更新缓存，避免滑动续期导致 TTL 永不过期
        let fromCache = cache.get()
        guard var credentials = fromCache ?? credentialLoader.loadCredentials() else {
            AppLog.probes.error("Claude API: No credentials found")
            throw ProbeError.authenticationRequired
        }
        if fromCache == nil {
            cache.set(credentials)
        }

        // Check if token needs refresh
        if credentialLoader.needsRefresh(credentials.oauth) {
            if credentials.oauth.refreshToken != nil {
                AppLog.probes.info("Claude API: Token expired or expiring soon, refreshing...")
                do {
                    credentials = try await refreshToken(credentials)
                } catch let refreshError {
                    // Clear cache so next probe reloads from file (CLI may have re-authenticated)
                    // 清除缓存，下次 probe 会从文件重新加载（CLI 可能已重新登录）
                    cache.clear()

                    // Try reloading from file — CLI may have updated credentials externally
                    // 尝试从文件重新加载——CLI 可能已在外部更新了凭证
                    if let freshCredentials = credentialLoader.loadCredentials(),
                       freshCredentials.oauth != credentials.oauth {
                        AppLog.probes.info("Claude API: Found updated credentials from file, retrying...")
                        credentials = freshCredentials
                        cache.set(credentials)
                        // Re-check if the fresh credentials also need refresh
                        if credentialLoader.needsRefresh(credentials.oauth) {
                            do {
                                credentials = try await refreshToken(credentials)
                            } catch {
                                AppLog.probes.error("Claude API: Retry with fresh credentials also failed: \(error.localizedDescription)")
                                cache.clear()
                                throw error
                            }
                        }
                        // Fresh credentials are valid, continue to fetch usage
                    } else {
                        AppLog.probes.error("Claude API: Token refresh failed: \(refreshError.localizedDescription)")
                        throw refreshError
                    }
                }
            } else {
                // Long-lived token (e.g. from `claude setup-token`) — no refresh mechanism.
                // Proceed directly with the token; the API call will fail with 401 if it's actually expired.
                AppLog.probes.info("Claude API: Token has no expiry info and no refresh token (setup-token), proceeding...")
            }
        }

        // Fetch usage data
        let usageData: UsageResponse
        do {
            usageData = try await fetchUsage(accessToken: credentials.oauth.accessToken)
        } catch let error as ProbeError where error == .authenticationRequired {
            // Token might have been invalidated, try refreshing once
            // Token 可能已被外部失效，尝试刷新一次
            if credentials.oauth.refreshToken != nil {
                AppLog.probes.info("Claude API: Got 401/403, attempting token refresh...")
                do {
                    credentials = try await refreshToken(credentials)
                    usageData = try await fetchUsage(accessToken: credentials.oauth.accessToken)
                } catch {
                    // Clear cache on auth failure so next probe reloads from file
                    // 认证失败时清除缓存，下次 probe 从文件重新加载
                    cache.clear()
                    AppLog.probes.error("Claude API: Retry after refresh failed: \(error.localizedDescription)")
                    throw error
                }
            } else {
                // No refresh token (setup-token) — can't recover from 401/403
                AppLog.probes.error("Claude API: Got 401/403 with no refresh token available")
                cache.clear()
                throw error
            }
        }

        let snapshot = parseUsageResponse(usageData, subscriptionType: credentials.oauth.subscriptionType)
        snapshotCache.set(snapshot)
        return snapshot
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
                    cache.clear()
                    throw ProbeError.sessionExpired(hint: "Run `claude` in terminal to log in again.")
                }
            }
            AppLog.probes.error("Claude API: Token expired or invalid (HTTP \(httpResponse.statusCode))")
            cache.clear()
            throw ProbeError.sessionExpired(hint: "Run `claude` in terminal to log in again.")
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

        // Save updated credentials and update cache
        credentialLoader.saveCredentials(updatedCredentials)
        cache.set(updatedCredentials)

        AppLog.probes.info("Claude API: Token refreshed successfully")
        return updatedCredentials
    }

    // MARK: - Usage Fetch

    private func fetchUsage(accessToken: String) async throws -> UsageResponse {
        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
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
        case 429:
            let retryAfter = Self.parseRetryAfter(
                httpResponse.value(forHTTPHeaderField: "Retry-After")
            ) ?? Self.defaultRetryAfter
            let retryAt = Date().addingTimeInterval(retryAfter)
            rateLimit.set(retryAt: retryAt)
            AppLog.probes.warning("Claude API: Rate limited (HTTP 429), retrying after \(Int(retryAfter))s")
            throw ProbeError.rateLimited(retryAt: retryAt)
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

        // Parse model-scoped limits from the generic `limits` array (e.g. Fable).
        // Session/weekly entries there mirror `five_hour`/`seven_day` and are
        // skipped; a model already covered by a legacy field is not duplicated.
        // If the legacy `five_hour`/`seven_day` fields ever go null (as
        // `seven_day_opus`/`seven_day_sonnet` did), extend this loop to the
        // `session`/`weekly_all` kinds.
        for entry in response.limits ?? [] {
            guard entry.kind == "weekly_scoped",
                  // Key on the first word of the display name ("Fable 5" -> "fable")
                  // — must stay in sync with the key the CLI probe hardcodes so a
                  // persisted "model:<name>" menu-bar selection survives switching
                  // probe modes.
                  let modelName = entry.scope?.model?.displayName?
                      .split(separator: " ").first.map({ $0.lowercased() }),
                  !modelName.isEmpty,
                  let percent = entry.percent else {
                continue
            }
            let quotaType = QuotaType.modelSpecific(modelName)
            guard !quotas.contains(where: { $0.quotaType == quotaType }) else {
                continue
            }
            let resetsAt = parseISODate(entry.resetsAt)
            quotas.append(UsageQuota(
                percentRemaining: 100.0 - percent,
                quotaType: quotaType,
                providerId: "claude",
                resetsAt: resetsAt,
                resetText: formatResetText(resetsAt)
            ))
        }

        // Prefer the current spend payload, then fall back to legacy
        // extra_usage. A shape with a present-but-invalid cap is dropped
        // (falls through) rather than reclassified as uncapped.
        let costUsage: CostUsage?
        if let pair = response.spend?.costPair {
            costUsage = CostUsage(
                totalCost: pair.used,
                budget: pair.cap,
                apiDuration: 0,
                providerId: "claude",
                kind: .extraUsage,
                capturedAt: Date(),
                resetsAt: nil,
                resetText: nil
            )
        } else if let pair = response.extraUsage?.costPair {
            costUsage = CostUsage(
                totalCost: pair.used,
                budget: pair.cap,
                apiDuration: 0,
                providerId: "claude",
                kind: .extraUsage,
                capturedAt: Date(),
                resetsAt: nil,
                resetText: nil
            )
        } else {
            costUsage = nil
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

    /// Parses an HTTP `Retry-After` header value into a duration.
    /// Per RFC 7231 the value is either a non-negative integer of seconds, or
    /// an HTTP-date. Returns nil for missing, malformed, or past-dated values
    /// so the caller can apply its own fallback.
    static func parseRetryAfter(_ value: String?, now: Date = Date()) -> TimeInterval? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else {
            return nil
        }
        // Reject 0 — the /api/oauth/usage endpoint has been observed returning
        // `Retry-After: 0` while continuing to 429, so treating 0 as "retry
        // immediately" lands us right back in a hammering loop. See
        // anthropics/claude-code#30930.
        if let seconds = TimeInterval(value), seconds > 0 {
            return seconds
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: value) else { return nil }
        let delta = date.timeIntervalSince(now)
        return delta > 0 ? delta : nil
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
    let spend: SpendData?
    let limits: [LimitEntry]?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayOpus = "seven_day_opus"
        case extraUsage = "extra_usage"
        case spend
        case limits
    }
}

/// Entry in the newer generic `limits` array. Model-scoped limits (e.g. Fable)
/// are reported here as `kind: "weekly_scoped"` with the model in `scope`,
/// instead of dedicated `seven_day_<model>` fields.
private struct LimitEntry: Decodable {
    let kind: String?
    let percent: Double?
    let resetsAt: String?
    let scope: LimitScope?

    enum CodingKeys: String, CodingKey {
        case kind
        case percent
        case resetsAt = "resets_at"
        case scope
    }
}

private struct LimitScope: Decodable {
    let model: LimitScopeModel?
}

private struct LimitScopeModel: Decodable {
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
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

private struct SpendData: Decodable {
    let used: MoneyData?
    let limit: MoneyData?
    let enabled: Bool?

    /// The decoded (used, cap) pair, or `nil` when the shape is disabled or
    /// invalid. A `nil` cap inside the pair means genuinely uncapped
    /// (`limit` absent or JSON null). A present-but-invalid `limit` poisons
    /// the whole shape instead of silently reading as "no monthly cap".
    var costPair: (used: Decimal, cap: Decimal?)? {
        guard enabled == true, let used = used?.amount else { return nil }
        guard let limit else { return (used, nil) }
        guard let cap = limit.amount else { return nil }
        return (used, cap)
    }
}

private struct MoneyData: Decodable {
    let amountMinor: Decimal?
    let currency: String?
    let exponent: Int?

    /// Negative spend is not a valid payload state; reject the row rather
    /// than silently flipping the sign.
    var amount: Decimal? {
        guard let amountMinor, amountMinor >= 0, let exponent, exponent >= 0 else { return nil }
        return Decimal(sign: .plus, exponent: -exponent, significand: amountMinor)
    }

    enum CodingKeys: String, CodingKey {
        case amountMinor = "amount_minor"
        case currency
        case exponent
    }
}

private struct ExtraUsageData: Decodable {
    let isEnabled: Bool?
    let usedCredits: Decimal?
    let monthlyLimit: Decimal?
    let decimalPlaces: Int?

    /// Same cap semantics as `SpendData.costPair`: absent/null limit means
    /// uncapped; a present-but-invalid limit invalidates the shape.
    var costPair: (used: Decimal, cap: Decimal?)? {
        guard isEnabled == true, let used = usedAmount else { return nil }
        guard monthlyLimit != nil else { return (used, nil) }
        guard let cap = monthlyLimitAmount else { return nil }
        return (used, cap)
    }

    var usedAmount: Decimal? {
        scaledAmount(usedCredits)
    }

    var monthlyLimitAmount: Decimal? {
        scaledAmount(monthlyLimit)
    }

    private func scaledAmount(_ amount: Decimal?) -> Decimal? {
        guard let amount, amount >= 0 else { return nil }
        let places = decimalPlaces ?? 2
        guard places >= 0 else { return nil }
        return Decimal(sign: .plus, exponent: -places, significand: amount)
    }

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case usedCredits = "used_credits"
        case monthlyLimit = "monthly_limit"
        case decimalPlaces = "decimal_places"
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
