import Diagnostics
import Quotas
import Foundation

/// OAuth 2's refresh-token grant (RFC 6749 §6): trades `refreshToken` for a
/// new `token`, and stamps `refreshedAt`. Which provider it serves is data.
struct OAuth2Refresher: CredentialRefreshing {
    let refresh: OAuth2Refresh
    let network: any NetworkClient
    let now: @Sendable () -> Date

    var retryStatuses: [Int] { refresh.onStatus }
    var writesBack: Bool { true }

    /// Never without a refresh token: there is nothing to trade.
    func isDue(_ credential: Credential) -> Bool {
        guard credential["refreshToken"] != nil else { return false }
        if let expiry = refresh.dueWhen {
            guard let raw = credential[expiry.expiresAt], let expiresAt = Self.instant(raw, unit: expiry.unit) else {
                return expiry.missingIsDue
            }
            return now().timeIntervalSince1970 + expiry.skew >= expiresAt
        }
        guard let every = refresh.every else { return false }
        guard let refreshedAt = credential["refreshedAt"].flatMap(Self.parseDate) else { return true }
        return now().timeIntervalSince(refreshedAt) > every
    }

    func refresh(_ credential: Credential) async throws -> Credential {
        // Nothing to trade: a key with no refresh token (a setup token, an
        // API-key login) that is refused is simply needed again.
        guard let refreshToken = credential["refreshToken"], !refreshToken.isEmpty else {
            throw UsageError.authenticationRequired
        }
        // The endpoint may be the credential's own issuer: `{{issuer}}/oauth2/token`.
        guard let url = Template.fill(refresh.tokenURL, with: credential).flatMap(Self.joinedURL) else {
            throw UsageError.authenticationRequired
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        var fields = [
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken),
        ]
        // A client the credential doesn't name is left out.
        if let clientId = Template.fill(refresh.clientId, with: credential), !clientId.isEmpty {
            fields.append(("client_id", clientId))
        }
        if let scope = refresh.scope { fields.append(("scope", scope)) }
        switch refresh.bodyFormat {
        case .form:
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.formBody(fields)
        case .json:
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: Dictionary(uniqueKeysWithValues: fields))
        }

        let (data, response) = try await network.request(request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageError.executionFailed("Invalid response from token refresh")
        }

        if http.statusCode == 400 || http.statusCode == 401 {
            let code = Self.errorCode(in: data)
            AppLog.probes.error("Token refresh refused (HTTP \(http.statusCode), \(code ?? "no code"))")
            throw UsageError.sessionExpired(hint: refresh.hint)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw UsageError.executionFailed("Token refresh failed: HTTP \(http.statusCode)")
        }

        guard let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let token = body["access_token"] as? String, !token.isEmpty else {
            throw UsageError.executionFailed("No access token in refresh response")
        }

        var renewed = credential
        renewed["token"] = token
        // An empty refresh token in the answer never replaces the saved one.
        if let newRefreshToken = body["refresh_token"] as? String, !newRefreshToken.isEmpty {
            renewed["refreshToken"] = newRefreshToken
        }
        if let idToken = body["id_token"] as? String {
            renewed["idToken"] = idToken
        }
        if let expiry = refresh.dueWhen, let expiresIn = JSONPath.number(body["expires_in"]) {
            let expiresAt = now().timeIntervalSince1970 + expiresIn
            renewed[expiry.expiresAt] = switch expiry.unit {
            case .seconds: String(Int64(expiresAt))
            case .milliseconds: String(Int64(expiresAt * 1000))
            case .iso8601: ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: expiresAt))
            }
        }
        renewed["refreshedAt"] = ISO8601DateFormatter().string(from: now())
        AppLog.probes.info("Token refreshed")
        return renewed
    }

    // MARK: - Helpers

    /// An expiry in its unit, as seconds since 1970.
    static func instant(_ raw: String, unit: OAuth2Refresh.Expiry.Unit) -> TimeInterval? {
        switch unit {
        case .seconds: Double(raw)
        case .milliseconds: Double(raw).map { $0 / 1000 }
        case .iso8601: ISO8601Instant.parse(raw)?.timeIntervalSince1970
        }
    }

    /// The URL with no doubled slash where an issuer ending in `/` meets a path.
    static func joinedURL(_ text: String) -> URL? {
        guard var components = URLComponents(string: text) else { return nil }
        while components.path.contains("//") {
            components.path = components.path.replacingOccurrences(of: "//", with: "/")
        }
        return components.url
    }

    static func formBody(_ fields: [(String, String)]) -> Data {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        let encoded = fields.map { name, value in
            "\(name)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }
        return Data(encoded.joined(separator: "&").utf8)
    }

    /// `{"error": {"code": …}}`, `{"error": "…"}` or `{"code": …}`.
    static func errorCode(in data: Data) -> String? {
        guard let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        if let error = body["error"] as? [String: Any], let code = error["code"] as? String { return code }
        if let error = body["error"] as? String { return error }
        return body["code"] as? String
    }

    static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
