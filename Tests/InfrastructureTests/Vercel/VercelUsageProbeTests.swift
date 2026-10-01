import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

@Suite
struct VercelUsageProbeTests {

    // MARK: - Sample Data

    static let sampleCreditsResponse = """
    {
      "balance": 95.50,
      "total_used": 4.50
    }
    """

    static let creditsURL = "https://ai-gateway.vercel.sh/v1/credits"

    // MARK: - Helper

    /// Creates a probe with test UserDefaults and mock network client.
    private func makeProbe(
        apiKey: String? = nil,
        envVar: String = "",
        environment: [String: String] = [:],
        networkClient: any NetworkClient = MockNetworkClient()
    ) -> VercelUsageProbe {
        let defaults = UserDefaults(suiteName: "VercelProbeTests.\(UUID().uuidString)")!
        let secureCredentials = UserDefaultsCredentialRepository(
            defaults: defaults,
            keyPrefix: "VercelProbeTests.secure."
        )
        let settingsRepository = UserDefaultsProviderSettingsRepository(
            userDefaults: defaults,
            secureCredentials: secureCredentials
        )
        settingsRepository.setVercelAuthEnvVar(envVar)
        if let apiKey {
            settingsRepository.saveVercelApiKey(apiKey)
        }
        return VercelUsageProbe(
            networkClient: networkClient,
            settingsRepository: settingsRepository,
            environment: environment
        )
    }

    // MARK: - isAvailable Tests

    @Test
    func `isAvailable returns false when no API key`() async {
        // Given: no API key configured, no env var
        let probe = makeProbe()

        // When & Then
        #expect(await probe.isAvailable() == false)
    }

    @Test
    func `isAvailable returns true when API key saved`() async {
        // Given
        let probe = makeProbe(apiKey: "test-key-123")

        // When & Then
        #expect(await probe.isAvailable() == true)
    }

    @Test
    func `isAvailable returns true when env var set`() async {
        let probe = makeProbe(environment: ["AI_GATEWAY_API_KEY": "env-key-456"])

        // When & Then
        #expect(await probe.isAvailable() == true)
    }

    // MARK: - probe Tests

    @Test
    func `probe returns UsageSnapshot on success`() async throws {
        // Given
        let mockNetwork = MockNetworkClient()
        let responseData = Data(Self.sampleCreditsResponse.utf8)
        let httpResponse = HTTPURLResponse(
            url: URL(string: Self.creditsURL)!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        given(mockNetwork)
            .request(.any)
            .willReturn((responseData, httpResponse))

        let probe = makeProbe(apiKey: "test-key", networkClient: mockNetwork)

        // When
        let snapshot = try await probe.probe()

        // Then
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas[0].dollarRemaining == Decimal(string: "95.50"))
        #expect(snapshot.providerId == "vercel-gateway")
    }

    @Test
    func `probe throws authenticationRequired when no API key`() async {
        // Given
        let probe = makeProbe()

        // When & Then
        await #expect(throws: ProbeError.authenticationRequired) {
            try await probe.probe()
        }
    }

    @Test
    func `probe throws authenticationRequired on HTTP 401`() async {
        // Given
        let mockNetwork = MockNetworkClient()
        let httpResponse = HTTPURLResponse(
            url: URL(string: Self.creditsURL)!,
            statusCode: 401,
            httpVersion: nil,
            headerFields: nil
        )!
        given(mockNetwork)
            .request(.any)
            .willReturn((Data(), httpResponse))

        let probe = makeProbe(apiKey: "bad-key", networkClient: mockNetwork)

        // When & Then
        await #expect(throws: ProbeError.authenticationRequired) {
            try await probe.probe()
        }
    }

    @Test
    func `probe throws executionFailed on HTTP 500`() async {
        // Given
        let mockNetwork = MockNetworkClient()
        let httpResponse = HTTPURLResponse(
            url: URL(string: Self.creditsURL)!,
            statusCode: 500,
            httpVersion: nil,
            headerFields: nil
        )!
        given(mockNetwork)
            .request(.any)
            .willReturn((Data(), httpResponse))

        let probe = makeProbe(apiKey: "test-key", networkClient: mockNetwork)

        // When & Then
        await #expect(throws: ProbeError.self) {
            try await probe.probe()
        }
    }

    @Test
    func `probe sends request to credits endpoint with Bearer auth`() async throws {
        // Given
        let mockNetwork = MockNetworkClient()
        let responseData = Data(Self.sampleCreditsResponse.utf8)
        let httpResponse = HTTPURLResponse(
            url: URL(string: Self.creditsURL)!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        var capturedRequest: URLRequest?
        given(mockNetwork)
            .request(.any)
            .willProduce { request in
                capturedRequest = request
                return (responseData, httpResponse)
            }

        let probe = makeProbe(apiKey: "test-key", networkClient: mockNetwork)

        // When
        _ = try await probe.probe()

        // Then: verify URL and Authorization header
        #expect(capturedRequest?.url?.absoluteString == Self.creditsURL)
        #expect(capturedRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        #expect(capturedRequest?.httpMethod == "GET")
    }

    @Test
    func `probe uses env var key when no stored key`() async throws {
        let mockNetwork = MockNetworkClient()
        let responseData = Data(Self.sampleCreditsResponse.utf8)
        let httpResponse = HTTPURLResponse(
            url: URL(string: Self.creditsURL)!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        var capturedRequest: URLRequest?
        given(mockNetwork)
            .request(.any)
            .willProduce { request in
                capturedRequest = request
                return (responseData, httpResponse)
            }

        let probe = makeProbe(
            environment: ["AI_GATEWAY_API_KEY": "env-key-789"],
            networkClient: mockNetwork
        )

        // When
        _ = try await probe.probe()

        // Then
        #expect(capturedRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer env-key-789")
    }

    @Test
    func `probe uses configured custom env var`() async throws {
        let mockNetwork = MockNetworkClient()
        let responseData = Data(Self.sampleCreditsResponse.utf8)
        let httpResponse = HTTPURLResponse(
            url: URL(string: Self.creditsURL)!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        var capturedRequest: URLRequest?
        given(mockNetwork)
            .request(.any)
            .willProduce { request in
                capturedRequest = request
                return (responseData, httpResponse)
            }

        let probe = makeProbe(
            envVar: "CUSTOM_VERCEL_KEY",
            environment: ["CUSTOM_VERCEL_KEY": "custom-env-key"],
            networkClient: mockNetwork
        )

        _ = try await probe.probe()

        #expect(capturedRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer custom-env-key")
    }

    @Test
    func `environment key takes precedence over stored key`() async throws {
        let mockNetwork = MockNetworkClient()
        let responseData = Data(Self.sampleCreditsResponse.utf8)
        let httpResponse = HTTPURLResponse(
            url: URL(string: Self.creditsURL)!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        var capturedRequest: URLRequest?
        given(mockNetwork)
            .request(.any)
            .willProduce { request in
                capturedRequest = request
                return (responseData, httpResponse)
            }

        let probe = makeProbe(
            apiKey: "stored-key",
            environment: ["AI_GATEWAY_API_KEY": "env-key"],
            networkClient: mockNetwork
        )

        _ = try await probe.probe()

        #expect(capturedRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer env-key")
    }

    @Test
    func `probe trims whitespace from stored API key`() async throws {
        let mockNetwork = MockNetworkClient()
        let responseData = Data(Self.sampleCreditsResponse.utf8)
        let httpResponse = HTTPURLResponse(
            url: URL(string: Self.creditsURL)!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        var capturedRequest: URLRequest?
        given(mockNetwork)
            .request(.any)
            .willProduce { request in
                capturedRequest = request
                return (responseData, httpResponse)
            }

        let probe = makeProbe(apiKey: "  stored-key\n", networkClient: mockNetwork)

        _ = try await probe.probe()

        #expect(capturedRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer stored-key")
    }

    @Test
    func `whitespace-only key is unavailable`() async {
        let probe = makeProbe(apiKey: " \n\t ")

        #expect(await probe.isAvailable() == false)
    }
}
