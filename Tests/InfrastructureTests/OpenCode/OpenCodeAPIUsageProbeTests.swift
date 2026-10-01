import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

@Suite("OpenCodeAPIUsageProbe Tests")
struct OpenCodeAPIUsageProbeTests {

    // MARK: - Helpers

    private func httpResponse(_ statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://opencode.ai/zen/go/v1/usage")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    private func loader(apiKey: String?) -> OpenCodeCredentialLoader {
        var env: [String: String] = ["XDG_DATA_HOME": "/nonexistent/\(UUID().uuidString)"]
        if let apiKey { env["OPENCODE_API_KEY"] = apiKey }
        return OpenCodeCredentialLoader(environment: env)
    }

    private static let errorJSON = Data(
        #"{"type":"error","error":{"type":"AuthError","message":"Unauthorized"}}"#.utf8
    )

    // MARK: - isAvailable

    @Test
    func `isAvailable is true when an API key exists`() async {
        let probe = OpenCodeAPIUsageProbe(credentialLoader: loader(apiKey: "k"), networkClient: MockNetworkClient())
        #expect(await probe.isAvailable() == true)
    }

    @Test
    func `isAvailable is false without a key and without a fallback`() async {
        let probe = OpenCodeAPIUsageProbe(credentialLoader: loader(apiKey: nil), networkClient: MockNetworkClient())
        #expect(await probe.isAvailable() == false)
    }

    @Test
    func `isAvailable defers to fallback when no key exists`() async {
        let fallback = MockUsageProbe()
        given(fallback).isAvailable().willReturn(true)

        let probe = OpenCodeAPIUsageProbe(
            credentialLoader: loader(apiKey: nil),
            networkClient: MockNetworkClient(),
            fallback: fallback
        )

        #expect(await probe.isAvailable() == true)
    }

    // MARK: - probe

    @Test
    func `probe sends bearer key and returns parsed snapshot`() async throws {
        let network = MockNetworkClient()
        let captured = CapturedRequest()
        given(network).request(.any).willProduce { request in
            captured.set(request)
            return (OpenCodeAPIUsageProbeParsingTests.usageJSON, self.httpResponse(200))
        }

        let probe = OpenCodeAPIUsageProbe(credentialLoader: loader(apiKey: "secret-key"), networkClient: network)
        let snapshot = try await probe.probe()

        #expect(snapshot.providerId == "opencode-go")
        #expect(snapshot.quotas.count == 3)
        #expect(captured.request?.url?.absoluteString == "https://opencode.ai/zen/go/v1/usage")
        #expect(captured.request?.value(forHTTPHeaderField: "Authorization") == "Bearer secret-key")
    }

    @Test
    func `probe throws authenticationRequired when no key and no fallback`() async {
        let probe = OpenCodeAPIUsageProbe(credentialLoader: loader(apiKey: nil), networkClient: MockNetworkClient())

        await #expect(throws: ProbeError.authenticationRequired) {
            try await probe.probe()
        }
    }

    @Test
    func `probe uses fallback when no key is available`() async throws {
        let fallback = MockUsageProbe()
        let fallbackSnapshot = UsageSnapshot(
            providerId: "opencode-go",
            quotas: [UsageQuota(percentRemaining: 42, quotaType: .session, providerId: "opencode-go")],
            capturedAt: Date()
        )
        given(fallback).probe().willReturn(fallbackSnapshot)

        let probe = OpenCodeAPIUsageProbe(
            credentialLoader: loader(apiKey: nil),
            networkClient: MockNetworkClient(),
            fallback: fallback
        )
        let snapshot = try await probe.probe()

        #expect(snapshot.quotas.first?.percentRemaining == 42)
    }

    @Test
    func `probe maps 401 to sessionExpired`() async {
        let network = MockNetworkClient()
        given(network).request(.any).willReturn((Self.errorJSON, httpResponse(401)))

        let probe = OpenCodeAPIUsageProbe(credentialLoader: loader(apiKey: "stale"), networkClient: network)

        await #expect(throws: ProbeError.sessionExpired()) {
            try await probe.probe()
        }
    }

    @Test
    func `probe maps 403 to subscriptionRequired`() async {
        let network = MockNetworkClient()
        let body = Data(#"{"type":"error","error":{"type":"EntitlementError","message":"OpenCode Go subscription required."}}"#.utf8)
        given(network).request(.any).willReturn((body, httpResponse(403)))

        let probe = OpenCodeAPIUsageProbe(credentialLoader: loader(apiKey: "k"), networkClient: network)

        await #expect(throws: ProbeError.subscriptionRequired) {
            try await probe.probe()
        }
    }

    @Test
    func `probe maps other HTTP errors to executionFailed`() async {
        let network = MockNetworkClient()
        given(network).request(.any).willReturn((Data(), httpResponse(503)))

        let probe = OpenCodeAPIUsageProbe(credentialLoader: loader(apiKey: "k"), networkClient: network)

        await #expect(throws: ProbeError.executionFailed("HTTP error: 503")) {
            try await probe.probe()
        }
    }

    @Test
    func `probe wraps transport errors as executionFailed`() async {
        let network = MockNetworkClient()
        given(network).request(.any).willThrow(URLError(.notConnectedToInternet))

        let probe = OpenCodeAPIUsageProbe(credentialLoader: loader(apiKey: "k"), networkClient: network)

        await #expect(throws: ProbeError.self) {
            try await probe.probe()
        }
    }
}

private final class CapturedRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var _request: URLRequest?
    var request: URLRequest? { lock.withLock { _request } }
    func set(_ r: URLRequest) { lock.withLock { _request = r } }
}
