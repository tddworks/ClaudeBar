import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

@Suite
struct AntigravityKeychainCredentialLoaderTests {

    static let tokenJSON = """
    {"token":{"access_token":"ya29.access","refresh_token":"1//refresh","expiry":"2030-01-01T00:00:00Z"},"email":"user@example.com"}
    """

    static var goKeyringWrapped: String {
        "go-keyring-base64:" + Data(tokenJSON.utf8).base64EncodedString()
    }

    // MARK: - Parsing

    @Test
    func `parses go-keyring-base64 wrapped token JSON`() {
        let creds = AntigravityKeychainCredentialLoader.parse(raw: Self.goKeyringWrapped)

        #expect(creds?.accessToken == "ya29.access")
        #expect(creds?.refreshToken == "1//refresh")
        #expect(creds?.expiresAt == ISO8601DateFormatter().date(from: "2030-01-01T00:00:00Z"))
    }

    @Test
    func `parses bare JSON with nested token object`() {
        let creds = AntigravityKeychainCredentialLoader.parse(raw: Self.tokenJSON)

        #expect(creds?.accessToken == "ya29.access")
        #expect(creds?.refreshToken == "1//refresh")
    }

    @Test
    func `parses JSON with tokens at the root`() {
        let raw = #"{"access_token":"root-access","refresh_token":"root-refresh"}"#

        let creds = AntigravityKeychainCredentialLoader.parse(raw: raw)

        #expect(creds?.accessToken == "root-access")
        #expect(creds?.refreshToken == "root-refresh")
        #expect(creds?.expiresAt == nil)
    }

    @Test
    func `returns nil for non-JSON keychain content`() {
        #expect(AntigravityKeychainCredentialLoader.parse(raw: "12345 /path/to/some_other_binary") == nil)
        #expect(AntigravityKeychainCredentialLoader.parse(raw: "") == nil)
        #expect(AntigravityKeychainCredentialLoader.parse(raw: "go-keyring-base64:not-base64!!") == nil)
    }

    @Test
    func `returns nil when JSON has neither access nor refresh token`() {
        #expect(AntigravityKeychainCredentialLoader.parse(raw: #"{"email":"x@y.z"}"#) == nil)
    }

    // MARK: - Credential behavior

    @Test
    func `access token is usable only when expiry is absent or in the future`() {
        let now = Date(timeIntervalSince1970: 1_000_000)

        let fresh = AntigravityOAuthCredentials(accessToken: "a", refreshToken: nil, expiresAt: now.addingTimeInterval(3600))
        let expiringSoon = AntigravityOAuthCredentials(accessToken: "a", refreshToken: nil, expiresAt: now.addingTimeInterval(30))
        let expired = AntigravityOAuthCredentials(accessToken: "a", refreshToken: nil, expiresAt: now.addingTimeInterval(-10))
        let unknown = AntigravityOAuthCredentials(accessToken: "a", refreshToken: nil, expiresAt: nil)
        let noAccess = AntigravityOAuthCredentials(accessToken: nil, refreshToken: "r", expiresAt: nil)

        #expect(fresh.hasUsableAccessToken(at: now))
        #expect(!expiringSoon.hasUsableAccessToken(at: now))
        #expect(!expired.hasUsableAccessToken(at: now))
        #expect(unknown.hasUsableAccessToken(at: now))
        #expect(!noAccess.hasUsableAccessToken(at: now))
    }

    // MARK: - Loading via security CLI

    @Test
    func `load returns credentials when security CLI succeeds`() async {
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor)
            .execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willReturn(CLIResult(output: Self.goKeyringWrapped + "\n", exitCode: 0))

        let loader = AntigravityKeychainCredentialLoader(cliExecutor: mockExecutor)

        #expect(await loader.load()?.accessToken == "ya29.access")
    }

    @Test
    func `load returns nil when keychain item is missing`() async {
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor)
            .execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willReturn(CLIResult(output: "security: SecKeychainSearchCopyNext: The specified item could not be found in the keychain.", exitCode: 44))

        let loader = AntigravityKeychainCredentialLoader(cliExecutor: mockExecutor)

        #expect(await loader.load() == nil)
    }
}
