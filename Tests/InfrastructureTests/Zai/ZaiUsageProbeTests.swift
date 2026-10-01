import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

@Suite
struct ZaiUsageProbeTests {

    // MARK: - Test Helpers

    private func makeSettingsRepository(
        apiKey: String? = nil,
        glmEnvVar: String = ""
    ) -> UserDefaultsProviderSettingsRepository {
        let suiteName = "com.claudebar.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let secureDefaults = UserDefaults(suiteName: suiteName + ".secure")!
        let repo = UserDefaultsProviderSettingsRepository(
            userDefaults: defaults,
            secureCredentials: UserDefaultsCredentialRepository(defaults: secureDefaults)
        )
        repo.setEnabled(true, forProvider: "zai")
        if let apiKey {
            repo.saveZaiApiKey(apiKey)
        }
        if !glmEnvVar.isEmpty {
            repo.setGlmAuthEnvVar(glmEnvVar)
        }
        return repo
    }

    private static func makeOKResponse() -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.z.ai/api/monitor/usage/quota/limit")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    // MARK: - Sample Data

    static let sampleQuotaLimitResponse = """
    {
      "data": {
        "limits": [
          {
            "type": "TOKENS_LIMIT",
            "percentage": 65,
            "nextResetTime": "2025-12-31T20:00:00Z"
          }
        ]
      }
    }
    """

    static let sampleClaudeConfigWithZai = """
    {
      "providers": [
        {
          "name": "anthropic",
          "base_url": "https://api.z.ai/api/anthropic",
          "api_key": "sk-zai-test-key-12345"
        }
      ]
    }
    """

    static let sampleClaudeConfigWithoutZai = """
    {
      "providers": [
        {
          "name": "anthropic",
          "base_url": "https://api.anthropic.com",
          "api_key": "sk-ant-test-key-12345"
        }
      ]
    }
    """

    static let sampleClaudeConfigEmpty = """
    {}
    """

    // MARK: - Configuration Detection Tests

    @Test
    func `isAvailable returns true when Claude config has zai endpoint`() async {
        // Given
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor).locate(.any).willReturn("/usr/local/bin/claude")

        // Simulate reading config file with z.ai endpoint
        given(mockExecutor).execute(
            binary: .any,
            args: .any,
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willReturn(CLIResult(output: Self.sampleClaudeConfigWithZai, exitCode: 0))

        let probe = ZaiUsageProbe(cliExecutor: mockExecutor, settingsRepository: makeSettingsRepository())

        // When & Then
        #expect(await probe.isAvailable() == true)
    }

    @Test
    func `isAvailable returns false when Claude config has no zai endpoint`() async {
        // Given
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor).locate(.any).willReturn("/usr/local/bin/claude")

        // Simulate reading config file without z.ai endpoint
        given(mockExecutor).execute(
            binary: .any,
            args: .any,
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willReturn(CLIResult(output: Self.sampleClaudeConfigWithoutZai, exitCode: 0))

        let probe = ZaiUsageProbe(cliExecutor: mockExecutor, settingsRepository: makeSettingsRepository())

        // When & Then
        #expect(await probe.isAvailable() == false)
    }

    @Test
    func `isAvailable returns false when Claude binary not found`() async {
        // Given
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor).locate(.any).willReturn(nil)

        let probe = ZaiUsageProbe(cliExecutor: mockExecutor, settingsRepository: makeSettingsRepository())

        // When & Then
        #expect(await probe.isAvailable() == false)
    }

    @Test
    func `isAvailable returns false when config file not readable`() async {
        // Given
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor).locate(.any).willReturn("/usr/local/bin/claude")

        // Simulate error reading config file
        given(mockExecutor).execute(
            binary: .any,
            args: .any,
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willThrow(ProbeError.executionFailed("File not found"))

        let probe = ZaiUsageProbe(cliExecutor: mockExecutor, settingsRepository: makeSettingsRepository())

        // When & Then
        #expect(await probe.isAvailable() == false)
    }

    @Test
    func `isAvailable returns true when ZHIPU endpoint in config`() async {
        // Given
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor).locate(.any).willReturn("/usr/local/bin/claude")

        // Simulate reading config file with ZHIPU endpoint
        let configWithZhipu = """
        {
          "providers": [
            {
              "name": "anthropic",
              "base_url": "https://open.bigmodel.cn/api/anthropic",
              "api_key": "test-key"
            }
          ]
        }
        """
        given(mockExecutor).execute(
            binary: .any,
            args: .any,
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willReturn(CLIResult(output: configWithZhipu, exitCode: 0))

        let probe = ZaiUsageProbe(cliExecutor: mockExecutor, settingsRepository: makeSettingsRepository())

        // When & Then
        #expect(await probe.isAvailable() == true)
    }

    // MARK: - Configuration Parsing Tests

    @Test
    func `extracts API key from Claude config`() {
        // Given
        let config = Self.sampleClaudeConfigWithZai

        // When
        let apiKey = ZaiUsageProbe.extractAPIKey(from: config)

        // Then
        #expect(apiKey == "sk-zai-test-key-12345")
    }

    @Test
    func `returns nil when API key not found`() {
        // Given
        let config = Self.sampleClaudeConfigEmpty

        // When
        let apiKey = ZaiUsageProbe.extractAPIKey(from: config)

        // Then
        #expect(apiKey == nil)
    }

    @Test
    func `detects platform from base URL`() {
        // Given
        let zaiConfig = Self.sampleClaudeConfigWithZai

        // When
        let platform = ZaiUsageProbe.detectPlatform(from: zaiConfig)

        // Then
        #expect(platform == .zai)
    }

    @Test
    func `detects ZHIPU platform from base URL`() {
        // Given
        let zhipuConfig = """
        {
          "providers": [
            {
              "base_url": "https://open.bigmodel.cn/api/anthropic"
            }
          ]
        }
        """

        // When
        let platform = ZaiUsageProbe.detectPlatform(from: zhipuConfig)

        // Then
        #expect(platform == .zhipu)
    }

    // MARK: - Probe Error Tests

    @Test
    func `probe throws cliNotFound when Claude not installed`() async throws {
        // Given
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor).locate(.any).willReturn(nil)

        let probe = ZaiUsageProbe(cliExecutor: mockExecutor, settingsRepository: makeSettingsRepository())

        // When & Then
        await #expect(throws: ProbeError.cliNotFound("Claude")) {
            try await probe.probe()
        }
    }

    @Test
    func `probe throws authenticationRequired when no API key found`() async throws {
        // Given
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor).locate(.any).willReturn("/usr/local/bin/claude")

        // Config without API key
        given(mockExecutor).execute(
            binary: .any,
            args: .any,
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willReturn(CLIResult(output: Self.sampleClaudeConfigEmpty, exitCode: 0))

        let probe = ZaiUsageProbe(cliExecutor: mockExecutor, settingsRepository: makeSettingsRepository())

        // When & Then
        await #expect(throws: ProbeError.authenticationRequired) {
            try await probe.probe()
        }
    }

    // MARK: - Full Probe Success Tests

    @Test
    func `probe returns snapshot when API call succeeds`() async throws {
        // Given
        let mockExecutor = MockCLIExecutor()
        let mockNetwork = MockNetworkClient()

        given(mockExecutor).locate(.any).willReturn("/usr/local/bin/claude")

        // Config with z.ai endpoint
        given(mockExecutor).execute(
            binary: .any,
            args: .any,
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willReturn(CLIResult(output: Self.sampleClaudeConfigWithZai, exitCode: 0))

        // API returns valid response
        let apiResponseData = Data(Self.sampleQuotaLimitResponse.utf8)
        let response = HTTPURLResponse(
            url: URL(string: "https://api.z.ai/api/monitor/usage/quota/limit")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        given(mockNetwork).request(.any).willReturn((apiResponseData, response))

        let probe = ZaiUsageProbe(
            cliExecutor: mockExecutor,
            networkClient: mockNetwork,
            settingsRepository: makeSettingsRepository()
        )

        // When
        let snapshot = try await probe.probe()

        // Then
        #expect(snapshot.providerId == "zai")
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas.first?.percentRemaining == 35.0) // 100 - 65 = 35
        #expect(snapshot.quotas.first?.resetsAt != nil)
    }

    // MARK: - API Error Tests

    @Test
    func `probe throws authenticationRequired when API returns 401`() async throws {
        // Given
        let mockExecutor = MockCLIExecutor()
        let mockNetwork = MockNetworkClient()

        given(mockExecutor).locate(.any).willReturn("/usr/local/bin/claude")

        given(mockExecutor).execute(
            binary: .any,
            args: .any,
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willReturn(CLIResult(output: Self.sampleClaudeConfigWithZai, exitCode: 0))

        // API returns 401
        let response = HTTPURLResponse(
            url: URL(string: "https://api.z.ai/api/monitor/usage/quota/limit")!,
            statusCode: 401,
            httpVersion: nil,
            headerFields: nil
        )!
        given(mockNetwork).request(.any).willReturn((Data(), response))

        let probe = ZaiUsageProbe(
            cliExecutor: mockExecutor,
            networkClient: mockNetwork,
            settingsRepository: makeSettingsRepository()
        )

        // When & Then
        await #expect(throws: ProbeError.authenticationRequired) {
            try await probe.probe()
        }
    }

    @Test
    func `probe throws executionFailed when API returns error status`() async throws {
        // Given
        let mockExecutor = MockCLIExecutor()
        let mockNetwork = MockNetworkClient()

        given(mockExecutor).locate(.any).willReturn("/usr/local/bin/claude")

        given(mockExecutor).execute(
            binary: .any,
            args: .any,
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willReturn(CLIResult(output: Self.sampleClaudeConfigWithZai, exitCode: 0))

        // API returns 500
        let response = HTTPURLResponse(
            url: URL(string: "https://api.z.ai/api/monitor/usage/quota/limit")!,
            statusCode: 500,
            httpVersion: nil,
            headerFields: nil
        )!
        given(mockNetwork).request(.any).willReturn((Data(), response))

        let probe = ZaiUsageProbe(
            cliExecutor: mockExecutor,
            networkClient: mockNetwork,
            settingsRepository: makeSettingsRepository()
        )

        // When & Then
        await #expect(throws: ProbeError.self) {
            try await probe.probe()
        }
    }

    @Test
    func `probe throws parseFailed when API returns invalid JSON`() async throws {
        // Given
        let mockExecutor = MockCLIExecutor()
        let mockNetwork = MockNetworkClient()

        given(mockExecutor).locate(.any).willReturn("/usr/local/bin/claude")

        given(mockExecutor).execute(
            binary: .any,
            args: .any,
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willReturn(CLIResult(output: Self.sampleClaudeConfigWithZai, exitCode: 0))

        // API returns invalid JSON
        let invalidData = Data("not valid json".utf8)
        let response = HTTPURLResponse(
            url: URL(string: "https://api.z.ai/api/monitor/usage/quota/limit")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        given(mockNetwork).request(.any).willReturn((invalidData, response))

        let probe = ZaiUsageProbe(
            cliExecutor: mockExecutor,
            networkClient: mockNetwork,
            settingsRepository: makeSettingsRepository()
        )

        // When & Then
        await #expect(throws: ProbeError.self) {
            try await probe.probe()
        }
    }

    // MARK: - Reset Date Parsing Tests

    @Test
    func `parseResetDate handles ISO-8601 with fractional seconds`() {
        let text = "2025-12-31T20:00:00.123Z"
        let date = ZaiUsageProbe.parseResetDate(.string(text))
        #expect(date != nil)
    }

    @Test
    func `parseResetDate handles ISO-8601 without fractional seconds`() {
        let text = "2025-12-31T20:00:00Z"
        let date = ZaiUsageProbe.parseResetDate(.string(text))
        #expect(date != nil)
    }

    @Test
    func `parseResetDate handles numeric timestamp`() {
        let timestamp: Int64 = 1767195236777
        let date = ZaiUsageProbe.parseResetDate(.timestamp(timestamp))
        #expect(date != nil)
        let calendar = Calendar(identifier: .gregorian)
        #expect(calendar.component(.year, from: date!) == 2025 || calendar.component(.year, from: date!) == 2026)
    }

    @Test
    func `parseResetDate returns nil for invalid format`() {
        let text = "invalid-date"
        let date = ZaiUsageProbe.parseResetDate(.string(text))
        #expect(date == nil)
    }

    // MARK: - Settings API Key Tests

    @Test
    func `probe prefers API key saved in settings over config file key`() async throws {
        // Given
        let mockExecutor = MockCLIExecutor()
        let mockNetwork = MockNetworkClient()

        given(mockExecutor).locate(.any).willReturn("/usr/local/bin/claude")

        given(mockExecutor).execute(
            binary: .any,
            args: .any,
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willReturn(CLIResult(output: Self.sampleClaudeConfigWithZai, exitCode: 0))

        given(mockNetwork).request(.matching { request in
            request.value(forHTTPHeaderField: "Authorization") == "Bearer settings-api-key"
        }).willReturn((Data(Self.sampleQuotaLimitResponse.utf8), Self.makeOKResponse()))

        let settings = makeSettingsRepository(apiKey: "settings-api-key", glmEnvVar: "GLM_TOKEN")
        let probe = ZaiUsageProbe(
            cliExecutor: mockExecutor,
            networkClient: mockNetwork,
            settingsRepository: settings
        )

        // When
        let snapshot = try await probe.probe()

        // Then
        #expect(snapshot.providerId == "zai")
        #expect(!snapshot.quotas.isEmpty)
    }

    @Test
    func `probe uses settings API key with default zai platform when config has no zai endpoint`() async throws {
        // Given
        let mockExecutor = MockCLIExecutor()
        let mockNetwork = MockNetworkClient()

        given(mockExecutor).locate(.any).willReturn("/usr/local/bin/claude")

        given(mockExecutor).execute(
            binary: .any,
            args: .any,
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willReturn(CLIResult(output: Self.sampleClaudeConfigWithoutZai, exitCode: 0))

        given(mockNetwork).request(.matching { request in
            request.url?.absoluteString.contains("api.z.ai") == true &&
            request.value(forHTTPHeaderField: "Authorization") == "Bearer settings-api-key"
        }).willReturn((Data(Self.sampleQuotaLimitResponse.utf8), Self.makeOKResponse()))

        let settings = makeSettingsRepository(apiKey: "settings-api-key")
        let probe = ZaiUsageProbe(
            cliExecutor: mockExecutor,
            networkClient: mockNetwork,
            settingsRepository: settings
        )

        // When
        let snapshot = try await probe.probe()

        // Then
        #expect(snapshot.providerId == "zai")
        #expect(!snapshot.quotas.isEmpty)
    }

    @Test
    func `isAvailable returns true when only a settings API key is configured`() async {
        // Given
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor).locate(.any).willReturn("/usr/local/bin/claude")

        given(mockExecutor).execute(
            binary: .any,
            args: .any,
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willReturn(CLIResult(output: Self.sampleClaudeConfigWithoutZai, exitCode: 0))

        let probe = ZaiUsageProbe(
            cliExecutor: mockExecutor,
            networkClient: MockNetworkClient(),
            settingsRepository: makeSettingsRepository(apiKey: "settings-api-key")
        )

        // When & Then
        #expect(await probe.isAvailable() == true)
    }

    @Test
    func `isAvailable returns true with settings key even when claude CLI is missing`() async {
        // Given
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor).locate(.any).willReturn(nil)

        given(mockExecutor).execute(
            binary: .any,
            args: .any,
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willReturn(CLIResult(output: Self.sampleClaudeConfigWithoutZai, exitCode: 0))

        let probe = ZaiUsageProbe(
            cliExecutor: mockExecutor,
            networkClient: MockNetworkClient(),
            settingsRepository: makeSettingsRepository(apiKey: "settings-api-key")
        )

        // When & Then
        #expect(await probe.isAvailable() == true)
    }

    @Test
    func `probe succeeds with settings key even when claude CLI is missing`() async throws {
        // Given
        let mockExecutor = MockCLIExecutor()
        let mockNetwork = MockNetworkClient()

        given(mockExecutor).locate(.any).willReturn(nil)

        given(mockExecutor).execute(
            binary: .any,
            args: .any,
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willReturn(CLIResult(output: Self.sampleClaudeConfigWithoutZai, exitCode: 0))

        given(mockNetwork).request(.matching { request in
            request.value(forHTTPHeaderField: "Authorization") == "Bearer settings-api-key"
        }).willReturn((Data(Self.sampleQuotaLimitResponse.utf8), Self.makeOKResponse()))

        let probe = ZaiUsageProbe(
            cliExecutor: mockExecutor,
            networkClient: mockNetwork,
            settingsRepository: makeSettingsRepository(apiKey: "settings-api-key")
        )

        // When
        let snapshot = try await probe.probe()

        // Then
        #expect(snapshot.providerId == "zai")
        #expect(!snapshot.quotas.isEmpty)
    }

    @Test
    func `probe throws authenticationRequired when settings API key is blank and no other source`() async throws {
        // Given
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor).locate(.any).willReturn("/usr/local/bin/claude")

        given(mockExecutor).execute(
            binary: .any,
            args: .any,
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willReturn(CLIResult(output: Self.sampleClaudeConfigWithoutZai, exitCode: 0))

        let probe = ZaiUsageProbe(
            cliExecutor: mockExecutor,
            networkClient: MockNetworkClient(),
            settingsRepository: makeSettingsRepository(apiKey: "   ")
        )

        // When & Then
        await #expect(throws: ProbeError.authenticationRequired) {
            try await probe.probe()
        }
    }
}
