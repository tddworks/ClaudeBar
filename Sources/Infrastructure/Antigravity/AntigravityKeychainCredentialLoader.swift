import Foundation
import Domain

/// OAuth credentials the Antigravity app / `agy` CLI already stored on this Mac.
public struct AntigravityOAuthCredentials: Sendable, Equatable {
    public let accessToken: String?
    public let refreshToken: String?
    public let expiresAt: Date?

    /// Treat a token with less than this left as expired and refresh proactively.
    static let refreshBuffer: TimeInterval = 60

    public init(accessToken: String?, refreshToken: String?, expiresAt: Date?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    /// Whether the stored access token is worth sending: present and (if the expiry is known) not about to expire.
    public func hasUsableAccessToken(at now: Date = Date()) -> Bool {
        guard let accessToken, !accessToken.isEmpty else { return false }
        guard let expiresAt else { return true }
        return expiresAt.timeIntervalSince(now) > Self.refreshBuffer
    }
}

/// Reads the Google OAuth token Antigravity / `agy` keep in the macOS Keychain
/// (generic password, service `gemini`, account `antigravity`).
///
/// The item is a `go-keyring-base64:`-wrapped JSON blob of the shape
/// `{ "token": { "access_token", "refresh_token", "expiry" }, ... }`.
/// This loader only ever reads it — it never writes back to Antigravity's item.
public struct AntigravityKeychainCredentialLoader: Sendable {
    static let keychainService = "gemini"
    static let keychainAccount = "antigravity"
    private static let goKeyringPrefix = "go-keyring-base64:"

    private let cliExecutor: any CLIExecutor
    private let timeout: TimeInterval

    public init(cliExecutor: any CLIExecutor = DefaultCLIExecutor(), timeout: TimeInterval = 8.0) {
        self.cliExecutor = cliExecutor
        self.timeout = timeout
    }

    /// Returns the stored credentials, or nil when the Keychain item is absent or unreadable.
    public func load() async -> AntigravityOAuthCredentials? {
        let result: CLIResult
        do {
            result = try await cliExecutor.execute(
                binary: "/usr/bin/security",
                args: ["find-generic-password", "-s", Self.keychainService, "-a", Self.keychainAccount, "-w"],
                input: nil,
                timeout: timeout,
                workingDirectory: nil,
                autoResponses: [:]
            )
        } catch {
            AppLog.credentials.error("Antigravity: Keychain read failed: \(error.localizedDescription)")
            return nil
        }

        guard result.exitCode == 0 else {
            AppLog.credentials.debug("Antigravity: no Keychain credentials (security exit code \(result.exitCode))")
            return nil
        }

        guard let credentials = Self.parse(raw: result.output) else {
            AppLog.credentials.error("Antigravity: Keychain credentials are in an unrecognized format")
            return nil
        }
        return credentials
    }

    // MARK: - Parsing (pure, for testability)

    static func parse(raw: String) -> AntigravityOAuthCredentials? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if text.hasPrefix(goKeyringPrefix) {
            let encoded = String(text.dropFirst(goKeyringPrefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = Data(base64Encoded: encoded),
                  let decoded = String(data: data, encoding: .utf8) else { return nil }
            text = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            return nil
        }
        return credentials(from: object)
    }

    private static func credentials(from object: [String: Any]) -> AntigravityOAuthCredentials? {
        let source = (object["token"] as? [String: Any]) ?? object
        let access = firstString(source, ["access_token", "accessToken"])
        let refresh = firstString(source, ["refresh_token", "refreshToken"])
        let expiry = firstString(source, ["expiry", "expires_at", "expiresAt"]).flatMap(parseDate)

        guard access != nil || refresh != nil else { return nil }
        return AntigravityOAuthCredentials(accessToken: access, refreshToken: refresh, expiresAt: expiry)
    }

    private static func firstString(_ object: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            if let value = (object[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        if let date = ISO8601DateFormatter().date(from: value) { return date }
        if let seconds = Double(value) { return Date(timeIntervalSince1970: seconds) }
        return nil
    }
}
