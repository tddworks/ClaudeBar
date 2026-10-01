import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

@Suite
struct DeepSeekUsageProbeTests {

    // MARK: - Sample Data

    static let sampleApiResponse = """
    {
      "is_available": true,
      "balance_infos": [
        {
          "currency": "USD",
          "total_balance": "40.00",
          "granted_balance": "10.00",
          "topped_up_balance": "30.00"
        }
      ]
    }
    """

    // MARK: - Helper

    /// Creates a probe with test UserDefaults and mock network client
    private func makeProbe(
        apiKey: String? = nil,
        envVar: String = "",
        networkClient: any NetworkClient = MockNetworkClient()
    ) -> DeepSeekUsageProbe {
        let defaults = UserDefaults(suiteName: "DeepSeekProbeTests.\(UUID().uuidString)")!
        let settingsRepository = UserDefaultsProviderSettingsRepository(userDefaults: defaults)
        settingsRepository.setDeepSeekAuthEnvVar(envVar)
        if let apiKey {
            settingsRepository.saveDeepSeekApiKey(apiKey)
        }
        return DeepSeekUsageProbe(
            networkClient: networkClient,
            settingsRepository: settingsRepository,
            // Deterministic: no env var in tests, regardless of the host environment
            environmentValue: { _ in nil }
        )
    }

    private func makeHTTPResponse(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.deepseek.com/user/balance")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
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
    func `isAvailable returns true when API key exists`() async {
        // Given
        let probe = makeProbe(apiKey: "test-key-123")

        // When & Then
        #expect(await probe.isAvailable() == true)
    }

    // MARK: - probe Tests

    @Test
    func `probe returns UsageSnapshot on success`() async throws {
        // Given
        let mockNetwork = MockNetworkClient()
        let responseData = Data(Self.sampleApiResponse.utf8)
        let httpResponse = makeHTTPResponse(statusCode: 200)
        given(mockNetwork)
            .request(.any)
            .willReturn((responseData, httpResponse))

        let probe = makeProbe(apiKey: "test-key", networkClient: mockNetwork)

        // When
        let snapshot = try await probe.probe()

        // Then
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas[0].quotaType == .modelSpecific("Balance"))
        #expect(snapshot.quotas[0].dollarRemaining == Decimal(40))
        #expect(snapshot.providerId == "deepseek")
    }

    @Test
    func `probe sends Bearer and Accept headers to the balance endpoint`() async throws {
        // Given
        let mockNetwork = MockNetworkClient()
        let responseData = Data(Self.sampleApiResponse.utf8)
        let httpResponse = makeHTTPResponse(statusCode: 200)
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

        // Then
        #expect(capturedRequest?.httpMethod == "GET")
        #expect(capturedRequest?.url?.absoluteString == "https://api.deepseek.com/user/balance")
        #expect(capturedRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        #expect(capturedRequest?.value(forHTTPHeaderField: "Accept") == "application/json")
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
        let httpResponse = makeHTTPResponse(statusCode: 401)
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
    func `probe throws authenticationRequired on HTTP 403`() async {
        // Given
        let mockNetwork = MockNetworkClient()
        let httpResponse = makeHTTPResponse(statusCode: 403)
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
        let httpResponse = makeHTTPResponse(statusCode: 500)
        given(mockNetwork)
            .request(.any)
            .willReturn((Data(), httpResponse))

        let probe = makeProbe(apiKey: "test-key", networkClient: mockNetwork)

        // When & Then: must be executionFailed specifically, not any ProbeError
        do {
            _ = try await probe.probe()
            Issue.record("Expected ProbeError.executionFailed")
        } catch {
            guard case ProbeError.executionFailed = error else {
                Issue.record("Expected ProbeError.executionFailed, got \(error)")
                return
            }
        }
    }
}
