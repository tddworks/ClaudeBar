import Foundation
import Domain

/// Grok OAuth credentials loaded from `~/.grok/auth.json`.
public struct GrokCredentialResult: @unchecked Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var email: String?
    public var expiresAt: String?
    public var oidcIssuer: String?
    public var oidcClientId: String?
    /// The top-level key this credential lives under (e.g. "https://auth.x.ai::<client-id>")
    public var entryKey: String
    public var fullData: [String: Any]

    public init(
        accessToken: String,
        refreshToken: String? = nil,
        email: String? = nil,
        expiresAt: String? = nil,
        oidcIssuer: String? = nil,
        oidcClientId: String? = nil,
        entryKey: String,
        fullData: [String: Any]
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.email = email
        self.expiresAt = expiresAt
        self.oidcIssuer = oidcIssuer
        self.oidcClientId = oidcClientId
        self.entryKey = entryKey
        self.fullData = fullData
    }
}

/// Loads Grok Build (xAI) OAuth credentials from `~/.grok/auth.json`.
///
/// The auth file is a dictionary keyed by "<issuer>::<client-id>" (OIDC login)
/// or a plain scope URL (legacy/API-key login):
/// ```json
/// {
///   "https://auth.x.ai::<client-id>": {
///     "key": "<access token>",
///     "auth_mode": "oidc",
///     "email": "user@example.com",
///     "refresh_token": "...",
///     "expires_at": "2026-07-26T21:03:09.138930Z",
///     "oidc_issuer": "https://auth.x.ai",
///     "oidc_client_id": "<client-id>"
///   }
/// }
/// ```
public struct GrokCredentialLoader: Sendable {
    private let homeDirectory: String

    /// Refresh this long before the token actually expires, so a probe never
    /// races the expiry mid-request.
    private static let expiryMargin: TimeInterval = 5 * 60

    public init(homeDirectory: String = NSHomeDirectory()) {
        self.homeDirectory = homeDirectory
    }

    /// The path to the auth file.
    public var authFilePath: String {
        (homeDirectory as NSString).appendingPathComponent(".grok/auth.json")
    }

    /// Loads credentials from `~/.grok/auth.json`.
    /// Returns nil when the file is missing or holds no usable token.
    /// When several entries exist, prefers one that can be refreshed
    /// (has a refresh token), then the one expiring furthest in the future.
    public func loadCredentials() -> GrokCredentialResult? {
        let path = authFilePath
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            var candidates: [GrokCredentialResult] = []
            for (entryKey, value) in json {
                guard let entry = value as? [String: Any],
                      let accessToken = entry["key"] as? String,
                      !accessToken.isEmpty else {
                    continue
                }
                let refreshToken = (entry["refresh_token"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                candidates.append(GrokCredentialResult(
                    accessToken: accessToken,
                    refreshToken: refreshToken,
                    email: entry["email"] as? String,
                    expiresAt: entry["expires_at"] as? String,
                    oidcIssuer: entry["oidc_issuer"] as? String,
                    oidcClientId: entry["oidc_client_id"] as? String,
                    entryKey: entryKey,
                    fullData: json
                ))
            }

            return candidates.max { lhs, rhs in
                let lhsRefreshable = lhs.refreshToken != nil
                let rhsRefreshable = rhs.refreshToken != nil
                if lhsRefreshable != rhsRefreshable {
                    return rhsRefreshable
                }
                let lhsExpiry = Self.parseDate(lhs.expiresAt) ?? .distantFuture
                let rhsExpiry = Self.parseDate(rhs.expiresAt) ?? .distantFuture
                return lhsExpiry < rhsExpiry
            }
        } catch {
            AppLog.credentials.error("Failed to load Grok credentials from file: \(error.localizedDescription)")
            return nil
        }
    }

    /// Whether the token should be refreshed before use.
    /// True when `expires_at` is within the expiry margin (or already past).
    /// Entries without an expiry (API-key style) never need a refresh.
    public func needsRefresh(expiresAt: String?) -> Bool {
        guard let expiresAt, let expiry = Self.parseDate(expiresAt) else {
            return false
        }
        return expiry.timeIntervalSinceNow < Self.expiryMargin
    }

    /// Saves refreshed token fields back into the credential's entry,
    /// preserving everything else in the file (other entries, enrichment fields).
    public func saveCredentials(_ result: GrokCredentialResult) {
        var updatedData = result.fullData

        var entry = (updatedData[result.entryKey] as? [String: Any]) ?? [:]
        entry["key"] = result.accessToken
        if let refreshToken = result.refreshToken {
            entry["refresh_token"] = refreshToken
        }
        if let expiresAt = result.expiresAt {
            entry["expires_at"] = expiresAt
        }
        updatedData[result.entryKey] = entry

        let path = authFilePath
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: updatedData, options: [.prettyPrinted, .sortedKeys])
            try jsonData.write(to: URL(fileURLWithPath: path), options: .atomic)
            AppLog.credentials.info("Saved updated Grok credentials to file")
        } catch {
            AppLog.credentials.error("Failed to save Grok credentials to file: \(error.localizedDescription)")
        }
    }

    /// Parses timestamps like "2026-07-26T21:03:09.138930Z" (microsecond
    /// fractions) or "2026-07-23T05:09:24.881042+00:00". ISO8601DateFormatter
    /// only accepts millisecond fractions, so the fraction is trimmed first.
    public static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }

        // Trim the fractional seconds to 3 digits (or drop them entirely)
        if let dotIndex = string.firstIndex(of: ".") {
            let fractionStart = string.index(after: dotIndex)
            var fractionEnd = fractionStart
            while fractionEnd < string.endIndex, string[fractionEnd].isNumber {
                fractionEnd = string.index(after: fractionEnd)
            }
            let fraction = string[fractionStart..<fractionEnd].prefix(3)
            let trimmed = string[..<dotIndex] + (fraction.isEmpty ? "" : "." + fraction) + string[fractionEnd...]
            if let date = formatter.date(from: String(trimmed)) {
                return date
            }
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
