import Foundation
import Domain

/// Command Code usage probe that fetches the same quota endpoints the `cmd`
/// CLI's `/usage` command uses.
///
/// Authentication is a long-lived API key from `COMMAND_CODE_API_KEY` (or
/// `~/.commandcode/auth.json`) — there is no token to refresh.
///
/// Whoami URL:  `https://api.commandcode.ai/alpha/whoami?limits=1`
/// Credits URL: `https://api.commandcode.ai/alpha/billing/credits`
public struct CommandCodeUsageProbe: UsageProbe, @unchecked Sendable {
    static let providerId = "commandcode"

    private let credentialLoader: CommandCodeCredentialLoader
    private let networkClient: any NetworkClient
    private let timeout: TimeInterval

    private static let whoamiURL = URL(string: "https://api.commandcode.ai/alpha/whoami?limits=1")!
    private static let creditsURL = URL(string: "https://api.commandcode.ai/alpha/billing/credits")!
    private static let reloginHint = "Run `cmd login` or set COMMAND_CODE_API_KEY."

    /// Plan id → monthly credit allowance in dollars.
    private static let planTotals: [String: Double] = [
        "individual-go": 10,
        "individual-goat": 70,
        "individual-pro": 30,
        "individual-pro-v1": 80,
        "individual-provider": 15,
        "individual-max": 150,
        "individual-ultra": 300,
        "teams-pro": 40,
    ]

    public init(
        credentialLoader: CommandCodeCredentialLoader = .init(),
        networkClient: any NetworkClient = URLSession.shared,
        timeout: TimeInterval = 15
    ) {
        self.credentialLoader = credentialLoader
        self.networkClient = networkClient
        self.timeout = timeout
    }

    public func isAvailable() async -> Bool {
        credentialLoader.loadAPIKey() != nil
    }

    public func probe() async throws -> UsageSnapshot {
        guard let apiKey = credentialLoader.loadAPIKey() else {
            AppLog.probes.error("Command Code: No API key found")
            throw ProbeError.authenticationRequired
        }

        let whoamiData = try await fetch(Self.whoamiURL, apiKey: apiKey)
        let whoami = Self.unwrap(whoamiData)
        let org = whoami["org"] as? [String: Any]
        let user = whoami["user"] as? [String: Any]
        let orgId = Self.stringValue(org?["id"]) ?? ""
        let account = Self.stringValue(user?["userName"]) ?? Self.stringValue(user?["name"])

        var components = URLComponents(url: Self.creditsURL, resolvingAgainstBaseURL: false)!
        if !orgId.isEmpty {
            components.queryItems = [URLQueryItem(name: "orgId", value: orgId)]
        }
        let creditsData = try await fetch(components.url!, apiKey: apiKey)

        return try Self.parseResponse(creditsData, providerId: Self.providerId, accountEmail: account)
    }

    // MARK: - HTTP

    private func fetch(_ url: URL, apiKey: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = timeout

        AppLog.probes.debug("Command Code: GET \(url.path)")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await networkClient.request(request)
        } catch {
            AppLog.probes.error("Command Code: Network error: \(error.localizedDescription)")
            throw ProbeError.executionFailed("Network error: \(error.localizedDescription)")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProbeError.executionFailed("Invalid response")
        }

        AppLog.probes.debug("Command Code: Response status \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200..<300:
            guard (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else {
                throw ProbeError.parseFailed("Failed to parse Command Code response as JSON")
            }
            return data
        case 401, 403:
            throw ProbeError.sessionExpired(hint: Self.reloginHint)
        default:
            AppLog.probes.error("Command Code: HTTP error \(httpResponse.statusCode)")
            throw ProbeError.executionFailed("HTTP error: \(httpResponse.statusCode)")
        }
    }

    // MARK: - Response Parsing

    static func parseResponse(
        _ data: Data,
        providerId: String,
        accountEmail: String? = nil,
        now: Date = Date()
    ) throws -> UsageSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProbeError.parseFailed("Failed to parse Command Code response as JSON")
        }

        return try parseCredits(root, providerId: providerId, accountEmail: accountEmail, now: now)
    }

    /// Parses the credits payload into a usage snapshot.
    ///
    /// Response shape (the `cmd` CLI reads this object as `a.data`):
    /// ```json
    /// {
    ///   "credits": {
    ///     "monthlyCredits": 8.5, "purchasedCredits": 0, "freeCredits": 0,
    ///     "planId": "individual-go"
    ///   },
    ///   "windowLimits": {
    ///     "fiveHour": { "used": 10, "cap": 40, "resetAt": 1770000000000 },
    ///     "weekly":   { "used": 50, "cap": 200, "resetAt": 1770500000000 }
    ///   }
    /// }
    /// ```
    static func parseCredits(
        _ root: [String: Any],
        providerId: String,
        accountEmail: String? = nil,
        now: Date = Date()
    ) throws -> UsageSnapshot {
        let payload = unwrap(root)
        var quotas: [UsageQuota] = []

        let windows = payload["windowLimits"] as? [String: Any]
        for (key, quotaType, duration) in windowMappings {
            guard let window = windows?[key] as? [String: Any],
                  let cap = doubleValue(window["cap"]), cap > 0 else {
                continue
            }
            let used = doubleValue(window["used"]) ?? 0
            quotas.append(UsageQuota(
                percentRemaining: (cap - used) / cap * 100,
                quotaType: quotaType,
                providerId: providerId,
                resetsAt: parseResetAt(window["resetAt"]),
                windowDuration: duration
            ))
        }

        if let creditQuota = creditQuota(payload: payload, providerId: providerId, hasWindowQuotas: !quotas.isEmpty) {
            quotas.append(creditQuota)
        }

        AppLog.probes.info("Command Code: Parsed \(quotas.count) quotas")

        return UsageSnapshot(
            providerId: providerId,
            quotas: quotas,
            capturedAt: now,
            accountEmail: accountEmail
        )
    }

    // MARK: - Parsing Helpers

    private static let windowMappings: [(key: String, quotaType: QuotaType, duration: TimeInterval)] = [
        ("fiveHour", .session, 5 * 3600),
        ("weekly", .weekly, 7 * 24 * 3600),
    ]

    /// Builds the monthly-credit meter from the plan's allowance.
    ///
    /// The plan id carries the allowance, so the meter only renders when the
    /// id is recognized. An unrecognized plan with no window limits still gets
    /// a balance-only meter rather than an empty card.
    private static func creditQuota(
        payload: [String: Any],
        providerId: String,
        hasWindowQuotas: Bool
    ) -> UsageQuota? {
        guard let credits = payload["credits"] as? [String: Any] else { return nil }

        let monthly = max(0, doubleValue(credits["monthlyCredits"]) ?? 0)
        let purchased = max(0, doubleValue(credits["purchasedCredits"]) ?? 0)
        let free = max(0, doubleValue(credits["freeCredits"]) ?? 0)
        let remaining = monthly + purchased + free

        // Longest key first so "individual-pro-v1" doesn't match "individual-pro".
        let normalized = (credits["planId"] as? String ?? "")
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        let planTotal = planTotals.keys
            .sorted { $0.count > $1.count }
            .first { normalized.hasPrefix($0) }
            .flatMap { planTotals[$0] }

        if let planTotal {
            let total = max(planTotal, monthly) + purchased + free
            guard total > 0 else { return nil }
            return UsageQuota(
                percentRemaining: remaining / total * 100,
                quotaType: .timeLimit("Credits"),
                providerId: providerId,
                dollarRemaining: Decimal(remaining),
                dollarUsed: Decimal(total - remaining),
                dollarCap: Decimal(total)
            )
        }

        guard !hasWindowQuotas, remaining > 0 else { return nil }
        return UsageQuota(
            percentRemaining: 100,
            quotaType: .timeLimit("Credits"),
            providerId: providerId,
            dollarRemaining: Decimal(remaining)
        )
    }

    /// Some deployments wrap the payload in a `data` object; the `cmd` CLI
    /// reads `a.data` from the credits call.
    private static func unwrap(_ root: [String: Any]) -> [String: Any] {
        (root["data"] as? [String: Any]) ?? root
    }

    private static func unwrap(_ data: Data) -> [String: Any] {
        unwrap((try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:])
    }

    /// Command Code reports `resetAt` as epoch milliseconds, epoch seconds, or
    /// an ISO-8601 string depending on the window.
    static func parseResetAt(_ value: Any?) -> Date? {
        if let number = value as? NSNumber {
            let raw = number.doubleValue
            return Date(timeIntervalSince1970: raw > 1e12 ? raw / 1000 : raw)
        }
        if let string = value as? String {
            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: string) { return date }
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: string)
        }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }
}
