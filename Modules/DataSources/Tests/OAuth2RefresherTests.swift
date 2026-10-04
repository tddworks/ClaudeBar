import Quotas
import Foundation
import Mockable
import Testing
@testable import DataSources

@Suite
struct OAuth2RefresherTests {

    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// An expiry in milliseconds, refreshed five minutes early, with a JSON body.
    private func refresher(network: any NetworkClient = MockNetworkClient(), bodyFormat: OAuth2Refresh.BodyFormat = .json) -> OAuth2Refresher {
        OAuth2Refresher(
            refresh: OAuth2Refresh(
                tokenURL: "https://auth.example.com/oauth/token",
                clientId: "client-1",
                onStatus: [401],
                hint: "Log in again.",
                bodyFormat: bodyFormat,
                scope: "read write",
                dueWhen: .init(expiresAt: "expiresAt", unit: .milliseconds, skew: 300)
            ),
            network: network,
            now: { Self.now }
        )
    }

    private func credential(expiresIn seconds: TimeInterval?, refreshToken: String? = "refresh-1") -> Credential {
        var values = ["token": "token-1"]
        if let refreshToken { values["refreshToken"] = refreshToken }
        if let seconds { values["expiresAt"] = String(Int64((Self.now.timeIntervalSince1970 + seconds) * 1000)) }
        return Credential(values)
    }

    private static func response(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://auth.example.com")!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    // MARK: - isDue

    @Test
    func `an expired token is due`() {
        #expect(refresher().isDue(credential(expiresIn: -3600)) == true)
    }

    @Test
    func `a token expiring within the skew is due`() {
        // 4 minutes left, less than the 5 minute skew
        #expect(refresher().isDue(credential(expiresIn: 4 * 60)) == true)
    }

    @Test
    func `a token with more than the skew left is not due`() {
        #expect(refresher().isDue(credential(expiresIn: 3600)) == false)
    }

    @Test
    func `a token with no expiry is due`() {
        #expect(refresher().isDue(credential(expiresIn: nil)) == true)
    }

    @Test
    func `a token with no refresh token is never due`() {
        // A long-lived setup token: no expiry and nothing to trade.
        #expect(refresher().isDue(credential(expiresIn: nil, refreshToken: nil)) == false)
        #expect(refresher().isDue(credential(expiresIn: -3600, refreshToken: nil)) == false)
    }

    // MARK: - refresh

    @Test
    func `a json refresh sends the grant, client id and scope`() async throws {
        let sent = SentRequest()
        let network = MockNetworkClient()
        given(network).request(.any).willProduce { @Sendable request in
            sent.request = request
            return (Data(#"{"access_token":"token-2"}"#.utf8), Self.response(200))
        }

        _ = try await refresher(network: network).refresh(credential(expiresIn: -60))

        let request = try #require(sent.request)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://auth.example.com/oauth/token")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try #require(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: String])
        #expect(body == [
            "grant_type": "refresh_token",
            "refresh_token": "refresh-1",
            "client_id": "client-1",
            "scope": "read write",
        ])
    }

    @Test
    func `a form refresh sends an encoded form body`() async throws {
        let sent = SentRequest()
        let network = MockNetworkClient()
        given(network).request(.any).willProduce { @Sendable request in
            sent.request = request
            return (Data(#"{"access_token":"token-2"}"#.utf8), Self.response(200))
        }

        _ = try await refresher(network: network, bodyFormat: .form).refresh(credential(expiresIn: -60))

        let request = try #require(sent.request)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        #expect(String(data: request.httpBody ?? Data(), encoding: .utf8)
            == "grant_type=refresh_token&refresh_token=refresh-1&client_id=client-1&scope=read%20write")
    }

    @Test
    func `a refresh stores the new tokens and expires_in as milliseconds`() async throws {
        let network = MockNetworkClient()
        given(network).request(.any).willReturn((
            Data(#"{"access_token":"token-2","refresh_token":"refresh-2","expires_in":3600}"#.utf8),
            Self.response(200)
        ))

        let renewed = try await refresher(network: network).refresh(credential(expiresIn: -60))

        #expect(renewed.token == "token-2")
        #expect(renewed["refreshToken"] == "refresh-2")
        #expect(renewed["expiresAt"] == "1700003600000")
        #expect(renewed["refreshedAt"] == "2023-11-14T22:13:20Z")
        #expect(refresher().isDue(renewed) == false)
    }

    @Test
    func `a refresh without a new refresh token keeps the old one`() async throws {
        let network = MockNetworkClient()
        given(network).request(.any).willReturn((Data(#"{"access_token":"token-2"}"#.utf8), Self.response(200)))

        let renewed = try await refresher(network: network).refresh(credential(expiresIn: -60))

        #expect(renewed["refreshToken"] == "refresh-1")
    }

    @Test
    func `a refused refresh means the session expired`() async throws {
        let network = MockNetworkClient()
        given(network).request(.any).willReturn((
            Data(#"{ "error": "invalid_grant", "error_description": "Refresh token has been revoked" }"#.utf8),
            Self.response(400)
        ))

        await #expect(throws: UsageError.sessionExpired(hint: "Log in again.")) {
            try await refresher(network: network).refresh(credential(expiresIn: -60))
        }
    }

    @Test
    func `a refresh answered with another error status fails to execute`() async throws {
        let network = MockNetworkClient()
        given(network).request(.any).willReturn((Data(), Self.response(503)))

        await #expect(throws: UsageError.executionFailed("Token refresh failed: HTTP 503")) {
            try await refresher(network: network).refresh(credential(expiresIn: -60))
        }
    }

    @Test
    func `a refresh with no refresh token needs authentication`() async throws {
        await #expect(throws: UsageError.authenticationRequired) {
            try await refresher().refresh(credential(expiresIn: nil, refreshToken: nil))
        }
    }

    // MARK: - A refresh whose endpoint the credential names

    private func issuerRefresher(network: any NetworkClient, missingIsDue: Bool = false) -> OAuth2Refresher {
        OAuth2Refresher(
            refresh: OAuth2Refresh(
                tokenURL: "{{issuer}}/oauth2/token", clientId: "{{clientId}}", onStatus: [401],
                hint: "Run `acme login` again.",
                dueWhen: .init(expiresAt: "expiresAt", unit: .iso8601, skew: 300, missingIsDue: missingIsDue)
            ),
            network: network, now: { Self.now }
        )
    }

    @Test
    func `an ISO 8601 expiry is due within the skew, and a missing one need not be`() {
        let expired = Credential(["token": "t", "refreshToken": "r", "expiresAt": "2023-11-14T22:13:00.123456Z"])
        let later = Credential(["token": "t", "refreshToken": "r", "expiresAt": "2023-11-15T22:13:20Z"])
        let none = Credential(["token": "t", "refreshToken": "r"])
        #expect(issuerRefresher(network: MockNetworkClient()).isDue(expired))
        #expect(issuerRefresher(network: MockNetworkClient()).isDue(later) == false)
        #expect(issuerRefresher(network: MockNetworkClient()).isDue(none) == false)
        #expect(issuerRefresher(network: MockNetworkClient(), missingIsDue: true).isDue(none))
    }

    @Test
    func `the token endpoint and client come from the credential, with no doubled slash`() async throws {
        let network = MockNetworkClient()
        let seen = RequestBox()
        given(network).request(.any).willProduce { request in
            seen.request = request
            return (Data(#"{"access_token":"new","refresh_token":"","expires_in":3600}"#.utf8), Self.response(200))
        }

        let renewed = try await issuerRefresher(network: network).refresh(
            Credential(["token": "old", "refreshToken": "r-1", "issuer": "https://login.acme.test/"]))

        #expect(seen.request?.url?.absoluteString == "https://login.acme.test/oauth2/token")
        #expect(String(decoding: seen.request?.httpBody ?? Data(), as: UTF8.self).contains("client_id") == false)
        #expect(renewed.token == "new")
        #expect(renewed["refreshToken"] == "r-1") // an empty refresh token never replaces the saved one
        #expect(renewed["expiresAt"]?.hasPrefix("2023-11-14T23:13:20") == true)
    }

    @Test
    func `with no refresh token there is nothing to trade, so the key is needed`() async {
        await #expect(throws: UsageError.authenticationRequired) {
            try await issuerRefresher(network: MockNetworkClient()).refresh(Credential(["token": "old", "issuer": "https://x.test"]))
        }
    }

}

/// The last request a stub received.
private final class SentRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var _request: URLRequest?

    var request: URLRequest? {
        get { lock.withLock { _request } }
        set { lock.withLock { _request = newValue } }
    }

}

private final class RequestBox: @unchecked Sendable {
    var request: URLRequest?
}
