import DataSources
import Quotas
import Foundation
import Mockable
import Testing

/// Where the `api` data source finds Claude's OAuth credentials — the file,
/// then the Keychain, then `CLAUDE_CODE_OAUTH_TOKEN` — and how a refreshed
/// token is written back. Ported from `ClaudeCredentialLoaderTests`; what the
/// loader returned is observed here as `hasKey` and the request's
/// `Authorization` header.
@Suite
struct ClaudeCredentialTests {

    private static let usageOK = #"{ "five_hour": { "utilization": 10.0 } }"#

    private static func isTokenRequest(_ request: URLRequest) -> Bool {
        request.url?.absoluteString.contains("oauth/token") == true
    }

    /// The `Authorization` header the usage request carried.
    private func authorization(_ claude: ClaudeHarness) async throws -> String? {
        let sent = Sent()
        given(claude.network).request(.any).willProduce { @Sendable request in
            if Self.isTokenRequest(request) {
                return (Data(#"{"error":"invalid_grant"}"#.utf8), ClaudeHarness.response(400))
            }
            sent.authorization = request.value(forHTTPHeaderField: "Authorization")
            return (Data(Self.usageOK.utf8), ClaudeHarness.response(200))
        }
        _ = try await claude.fetchUsage(try claude.dataSource("api"))
        return sent.authorization
    }

    private func writeRawCredentials(_ text: String, in claude: ClaudeHarness) throws {
        let directory = claude.home.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: directory.appendingPathComponent(".credentials.json"))
    }

    // MARK: - The credentials file

    @Test
    func `no key is found when the file does not exist`() throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }

        #expect(try claude.dataSource("api").hasKey == false)
    }

    @Test
    func `the file's access token and plan are used`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try claude.writeCredentials(
            accessToken: "my-access-token",
            refreshToken: "my-refresh-token",
            expiresAt: claude.now.addingTimeInterval(3600).timeIntervalSince1970 * 1000,
            subscriptionType: "claude_max"
        )
        given(claude.network).request(.any).willProduce { @Sendable request in
            request.value(forHTTPHeaderField: "Authorization") == "Bearer my-access-token"
                ? (Data(Self.usageOK.utf8), ClaudeHarness.response(200))
                : (Data(), ClaudeHarness.response(500))
        }

        let snapshot = try await claude.fetchUsage(try claude.dataSource("api"))

        #expect(snapshot.quotas.first?.percentRemaining == 90)
        #expect(snapshot.accountTier == .claudeMax)
    }

    @Test
    func `the file's refresh token is the one traded`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try claude.writeCredentials(
            refreshToken: "my-refresh-token",
            expiresAt: claude.now.addingTimeInterval(-3600).timeIntervalSince1970 * 1000
        )
        given(claude.network).request(.any).willProduce { @Sendable request in
            if Self.isTokenRequest(request) {
                let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] }
                return body?["refresh_token"] == "my-refresh-token"
                    ? (Data(#"{ "access_token": "new-token", "expires_in": 3600 }"#.utf8), ClaudeHarness.response(200))
                    : (Data(#"{"error":"invalid_grant"}"#.utf8), ClaudeHarness.response(400))
            }
            return (Data(Self.usageOK.utf8), ClaudeHarness.response(200))
        }

        _ = try await claude.fetchUsage(try claude.dataSource("api"))

        #expect(try claude.readCredentials()["accessToken"] as? String == "new-token")
    }

    @Test
    func `no key is found when the file's access token is empty`() throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try claude.writeCredentials(accessToken: "", refreshToken: "refresh")

        #expect(try claude.dataSource("api").hasKey == false)
    }

    @Test
    func `no key is found when the file is not json`() throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try writeRawCredentials("not valid json", in: claude)

        #expect(try claude.dataSource("api").hasKey == false)
    }

    @Test
    func `no key is found when the file has no claudeAiOauth`() throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try writeRawCredentials(#"{"someOtherKey":"value"}"#, in: claude)

        #expect(try claude.dataSource("api").hasKey == false)
    }

    // MARK: - Writing back

    @Test
    func `a refreshed token written back is the one read next time`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try claude.writeCredentials(
            accessToken: "old-token",
            refreshToken: "old-refresh",
            expiresAt: claude.now.addingTimeInterval(-3600).timeIntervalSince1970 * 1000
        )
        let refreshed = #"{ "access_token": "new-token", "refresh_token": "new-refresh", "expires_in": 3600 }"#
        let sent = Sent()
        given(claude.network).request(.any).willProduce { @Sendable request in
            if Self.isTokenRequest(request) {
                return (Data(refreshed.utf8), ClaudeHarness.response(200))
            }
            sent.authorization = request.value(forHTTPHeaderField: "Authorization")
            return (Data(Self.usageOK.utf8), ClaudeHarness.response(200))
        }
        _ = try await claude.fetchUsage(try claude.dataSource("api"))

        // A new data source reads the file afresh.
        _ = try await claude.fetchUsage(try claude.dataSource("api"))

        #expect(sent.authorization == "Bearer new-token")
        let saved = try claude.readCredentials()
        #expect(saved["accessToken"] as? String == "new-token")
        #expect(saved["refreshToken"] as? String == "new-refresh")
    }

    @Test
    func `writing back keeps the fields ClaudeBar does not read`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        // expiresAt is long past, so the token is refreshed.
        try claude.writeCredentials(
            accessToken: "old-token",
            refreshToken: "old-refresh",
            expiresAt: 1_748_276_587_173,
            extra: ["scopes": ["user:inference", "user:profile"]]
        )
        given(claude.network).request(.any).willProduce { @Sendable request in
            Self.isTokenRequest(request)
                ? (Data(#"{ "access_token": "new-token", "expires_in": 3600 }"#.utf8), ClaudeHarness.response(200))
                : (Data(Self.usageOK.utf8), ClaudeHarness.response(200))
        }

        _ = try await claude.fetchUsage(try claude.dataSource("api"))

        let saved = try claude.readCredentials()
        #expect(saved["accessToken"] as? String == "new-token")
        #expect(saved["scopes"] as? [String] == ["user:inference", "user:profile"])
        #expect(saved["expiresAt"] is NSNumber)
        #expect(saved["expiresAt"] is String == false)
    }

    // MARK: - The Keychain

    @Test
    func `the Keychain item is read when there is no file`() async throws {
        var claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        claude.keychainPassword = #"{"claudeAiOauth":{"accessToken":"keychain-token","subscriptionType":"claude_pro"}}"#

        #expect(try await authorization(claude) == "Bearer keychain-token")
    }

    @Test
    func `a hex-encoded Keychain payload from an older build is decoded`() async throws {
        var claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        let json = #"{"claudeAiOauth":{"accessToken":"hex-token"}}"#
        claude.keychainPassword = json.utf8.map { String(format: "%02x", $0) }.joined()

        #expect(try await authorization(claude) == "Bearer hex-token")
    }

    @Test
    func `the file is preferred over the Keychain`() async throws {
        var claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try claude.writeCredentials(accessToken: "file-token")
        claude.keychainPassword = #"{"claudeAiOauth":{"accessToken":"keychain-token"}}"#

        #expect(try await authorization(claude) == "Bearer file-token")
    }

    @Test
    func `the Keychain is preferred over the environment`() async throws {
        var claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        claude.keychainPassword = #"{"claudeAiOauth":{"accessToken":"keychain-token"}}"#
        claude.environment = ["CLAUDE_CODE_OAUTH_TOKEN": "env-token"]

        #expect(try await authorization(claude) == "Bearer keychain-token")
    }

    // MARK: - CLAUDE_CODE_OAUTH_TOKEN

    @Test
    func `the environment token is used when nothing else answers`() async throws {
        var claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        claude.environment = ["CLAUDE_CODE_OAUTH_TOKEN": "my-setup-token"]

        #expect(try await authorization(claude) == "Bearer my-setup-token")
    }

    @Test
    func `the environment token is never refreshed and never written to a file`() async throws {
        var claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        claude.environment = ["CLAUDE_CODE_OAUTH_TOKEN": "my-setup-token"]

        // `authorization` answers any refresh with invalid_grant: the fetch
        // succeeding shows none was tried.
        #expect(try await authorization(claude) == "Bearer my-setup-token")
        #expect(!FileManager.default.fileExists(atPath: claude.home.appendingPathComponent(".claude/.credentials.json").path))
    }

    @Test
    func `the environment token is trimmed of whitespace and newlines`() async throws {
        var claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        claude.environment = ["CLAUDE_CODE_OAUTH_TOKEN": "  my-setup-token\n"]

        #expect(try await authorization(claude) == "Bearer my-setup-token")
    }

    @Test
    func `the file is preferred over the environment token`() async throws {
        var claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        // Full-scope credentials from `claude login`
        try claude.writeCredentials(accessToken: "file-token", refreshToken: "file-refresh")
        claude.environment = ["CLAUDE_CODE_OAUTH_TOKEN": "env-token"]

        #expect(try await authorization(claude) == "Bearer file-token")
    }

    @Test
    func `an empty environment token is no key`() throws {
        var claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        claude.environment = ["CLAUDE_CODE_OAUTH_TOKEN": ""]

        #expect(try claude.dataSource("api").hasKey == false)
    }

    @Test
    func `an empty environment token falls through to the file`() async throws {
        var claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try claude.writeCredentials(accessToken: "file-token")
        claude.environment = ["CLAUDE_CODE_OAUTH_TOKEN": ""]

        #expect(try await authorization(claude) == "Bearer file-token")
    }

    @Test
    func `the file is used when the environment variable is absent`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try claude.writeCredentials(accessToken: "file-token")

        #expect(try await authorization(claude) == "Bearer file-token")
    }
}

/// What a stubbed request carried, read after the fetch.
private final class Sent: @unchecked Sendable {
    private let lock = NSLock()
    private var _authorization: String?

    var authorization: String? {
        get { lock.withLock { _authorization } }
        set { lock.withLock { _authorization = newValue } }
    }
}
