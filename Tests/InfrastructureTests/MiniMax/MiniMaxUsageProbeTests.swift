import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

@Suite
struct MiniMaxUsageProbeTests {

    // MARK: - Sample Data

    static let sampleApiResponse = """
    {
      "base_resp": { "status_code": 0, "status_msg": "success" },
      "model_remains": [
        {
          "model_name": "minimax-m2",
          "current_interval_total_count": 1500,
          "current_interval_usage_count": 255,
          "remains_time": 1234,
          "end_time": 1735689600000
        }
      ]
    }
    """

    // MARK: - Helper

    /// Creates a probe with test UserDefaults and mock network client
    /// Pass nil for region to test the "not configured" fallback path (传 nil 测试未配置 region 的回退路径)
    private func makeProbe(
        apiKey: String? = nil,
        envVar: String = "",
        region: MiniMaxRegion? = .china,
        networkClient: any NetworkClient = MockNetworkClient()
    ) -> MiniMaxUsageProbe {
        let defaults = UserDefaults(suiteName: "MiniMaxProbeTests.\(UUID().uuidString)")!
        let settingsRepository = UserDefaultsProviderSettingsRepository(userDefaults: defaults)
        if let region {
            settingsRepository.setMinimaxRegion(region)
        }
        settingsRepository.setMinimaxAuthEnvVar(envVar)
        if let apiKey {
            settingsRepository.saveMinimaxApiKey(apiKey)
        }
        return MiniMaxUsageProbe(
            networkClient: networkClient,
            settingsRepository: settingsRepository
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
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.minimaxi.com/v1/token_plan/remains")!,
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
        #expect(snapshot.quotas[0].quotaType == .modelSpecific("minimax-m2"))
        #expect(snapshot.providerId == "minimax")
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
    func `probe throws on HTTP 401 error`() async {
        // Given
        let mockNetwork = MockNetworkClient()
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.minimaxi.com/v1/token_plan/remains")!,
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
    func `probe throws on HTTP 500 error`() async {
        // Given
        let mockNetwork = MockNetworkClient()
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.minimaxi.com/v1/token_plan/remains")!,
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

    // MARK: - Region Tests

    @Test
    func `apiURL defaults to china when region not configured`() {
        // Given: no region set, simulating legacy user upgrade (模拟旧版用户升级，未配置 region)
        let probe = makeProbe(apiKey: "test-key", region: nil)

        // Then: falls back to china for backward compatibility (兼容旧版默认中国区)
        #expect(probe.apiURL == "https://api.minimaxi.com/v1/token_plan/remains")
    }

    @Test
    func `apiURL uses china region when explicitly configured`() {
        // Given
        let probe = makeProbe(apiKey: "test-key", region: .china)

        // Then
        #expect(probe.apiURL == "https://api.minimaxi.com/v1/token_plan/remains")
    }

    @Test
    func `apiURL uses international region when configured`() {
        // Given
        let probe = makeProbe(apiKey: "test-key", region: .international)

        // Then
        #expect(probe.apiURL == "https://api.minimax.io/v1/token_plan/remains")
    }

    @Test
    func `probe uses international API URL when region is international`() async throws {
        // Given
        let mockNetwork = MockNetworkClient()
        let responseData = Data(Self.sampleApiResponse.utf8)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.minimax.io/v1/token_plan/remains")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        // Capture the request to verify URL (捕获请求以验证 URL)
        var capturedRequest: URLRequest?
        given(mockNetwork)
            .request(.any)
            .willProduce { request in
                capturedRequest = request
                return (responseData, httpResponse)
            }

        let probe = makeProbe(apiKey: "test-key", region: .international, networkClient: mockNetwork)

        // When
        let snapshot = try await probe.probe()

        // Then: verify response parsing
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.providerId == "minimax")
        // Verify the request was sent to international endpoint (验证请求发送到国际版端点)
        #expect(capturedRequest?.url?.absoluteString == "https://api.minimax.io/v1/token_plan/remains")
    }
}
