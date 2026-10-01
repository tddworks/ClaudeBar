import Foundation
import Domain

/// Fetches OpenCode Go usage from the official usage endpoint
/// (`GET https://opencode.ai/zen/go/v1/usage`, anomalyco/opencode#16513).
///
/// The server computes the same rolling / weekly / monthly figures the
/// opencode.ai dashboard shows, so this replaces the local-DB estimate
/// (which only sees this machine's messages). When no API key is configured
/// the probe defers to an optional `fallback` (typically `OpenCodeUsageProbe`).
///
/// Response shape:
/// ```json
/// { "usage": {
///     "rolling": { "status": "ok", "percent": 17, "resetsAt": "2026-08-24T12:00:00.000Z" },
///     "weekly":  { ... },
///     "monthly": { ... } } }
/// ```
/// `percent` is *used*; `status` is `"ok"` or `"rate-limited"`.
public struct OpenCodeAPIUsageProbe: UsageProbe, @unchecked Sendable {
    static let usageURL = URL(string: "https://opencode.ai/zen/go/v1/usage")!
    static let providerId = "opencode-go"
    private static let reloginHint = "Run `opencode auth login` and pick OpenCode Zen to refresh your API key."

    private let credentialLoader: OpenCodeCredentialLoader
    private let networkClient: any NetworkClient
    private let fallback: (any UsageProbe)?
    private let timeout: TimeInterval

    public init(
        credentialLoader: OpenCodeCredentialLoader = OpenCodeCredentialLoader(),
        networkClient: any NetworkClient = URLSession.shared,
        fallback: (any UsageProbe)? = nil,
        timeout: TimeInterval = 15
    ) {
        self.credentialLoader = credentialLoader
        self.networkClient = networkClient
        self.fallback = fallback
        self.timeout = timeout
    }

    // MARK: - UsageProbe

    public func isAvailable() async -> Bool {
        if credentialLoader.loadAPIKey() != nil {
            return true
        }
        if let fallback {
            return await fallback.isAvailable()
        }
        return false
    }

    public func probe() async throws -> UsageSnapshot {
        guard let apiKey = credentialLoader.loadAPIKey() else {
            if let fallback {
                AppLog.probes.info("OpenCode: No API key found, falling back to local DB probe")
                return try await fallback.probe()
            }
            AppLog.probes.error("OpenCode: No API key found")
            throw ProbeError.authenticationRequired
        }

        let data = try await fetchUsage(apiKey: apiKey)
        let snapshot = try Self.parseResponse(data)

        let summary = snapshot.quotas
            .map { "\($0.quotaType.displayName) \(Int($0.percentRemaining))%" }
            .joined(separator: ", ")
        AppLog.probes.info("OpenCode API probe success: \(summary)")

        return snapshot
    }

    // MARK: - Network

    private func fetchUsage(apiKey: String) async throws -> Data {
        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = timeout

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await networkClient.request(request)
        } catch {
            AppLog.probes.error("OpenCode: Network error: \(error.localizedDescription)")
            throw ProbeError.executionFailed("Network error: \(error.localizedDescription)")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProbeError.executionFailed("Invalid response")
        }

        switch httpResponse.statusCode {
        case 200:
            return data
        case 401:
            AppLog.probes.error("OpenCode: API key rejected (HTTP 401)")
            throw ProbeError.sessionExpired(hint: Self.reloginHint)
        case 403:
            AppLog.probes.error("OpenCode: No Go subscription for this key (HTTP 403)")
            throw ProbeError.subscriptionRequired
        default:
            AppLog.probes.error("OpenCode: HTTP error \(httpResponse.statusCode)")
            throw ProbeError.executionFailed("HTTP error: \(httpResponse.statusCode)")
        }
    }

    // MARK: - Parsing (testable)

    private struct Window {
        let key: String
        let quotaType: QuotaType
        let duration: TimeInterval?
    }

    private static let windows: [Window] = [
        Window(key: "rolling", quotaType: .session, duration: 5 * 3600),
        Window(key: "weekly", quotaType: .weekly, duration: 7 * 86400),
        Window(key: "monthly", quotaType: .timeLimit("Monthly"), duration: nil),
    ]

    static func parseResponse(_ data: Data, now: Date = Date()) throws -> UsageSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProbeError.parseFailed("Failed to parse usage response as JSON")
        }
        guard let usage = root["usage"] as? [String: Any] else {
            throw ProbeError.parseFailed("Missing 'usage' in response")
        }

        var quotas: [UsageQuota] = []
        for window in windows {
            guard let entry = usage[window.key] as? [String: Any],
                  let percentUsed = doubleValue(entry["percent"]) else {
                continue
            }
            let rateLimited = (entry["status"] as? String) == "rate-limited"
            let remaining = rateLimited ? 0 : max(0, min(100, 100 - percentUsed))

            quotas.append(UsageQuota(
                percentRemaining: remaining,
                quotaType: window.quotaType,
                providerId: providerId,
                resetsAt: parseDate(entry["resetsAt"] as? String),
                windowDuration: window.duration
            ))
        }

        guard !quotas.isEmpty else {
            throw ProbeError.parseFailed("No usage windows in response")
        }

        return UsageSnapshot(providerId: providerId, quotas: quotas, capturedAt: now)
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let d as Double: return d
        case let i as Int: return Double(i)
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }

    private static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
