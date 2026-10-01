import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

@Suite("ZaiUsageProbe Environment Variable Fallback Tests")
struct ZaiUsageProbeEnvVarFallbackTests {

    static let sampleConfigWithKey = """
    {
        "env": {
            "ANTHROPIC_BASE_URL": "https://api.z.ai",
            "ANTHROPIC_AUTH_TOKEN": "config-api-key"
        }
    }
    """

    static let sampleConfigWithoutKey = """
    {
        "env": {
            "ANTHROPIC_BASE_URL": "https://api.z.ai"
        }
    }
    """

    static let sampleQuotaResponse = """
    {
      "data": {
        "limits": [
          {
            "type": "TOKENS_LIMIT",
            "percentage": 40,
            "nextResetTime": "2025-12-31T20:00:00Z"
          }
        ]
      }
    }
    """

    private func makeOKResponse() -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.z.ai/api/monitor/usage/quota/limit")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    private func stubConfigRead(_ mockExecutor: MockCLIExecutor, config: String) {
        given(mockExecutor).execute(
            binary: .matching { $0 == "cat" },
            args: .any,
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willReturn(CLIResult(output: config, exitCode: 0))
    }

    private func stubLoginShell(_ mockExecutor: MockCLIExecutor, output: String, exitCode: Int32 = 0) {
        let wrapped = "\(LoginShellEnvironment.beginMarker)\(output)\(LoginShellEnvironment.endMarker)\n"
        given(mockExecutor).execute(
            binary: .matching { $0 != "cat" },
            args: .any,
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willReturn(CLIResult(output: wrapped, exitCode: exitCode))
    }

    private func makeSettingsRepository(
        zaiPath: String = "",
        glmEnvVar: String = ""
    ) -> UserDefaultsProviderSettingsRepository {
        let suiteName = "com.claudebar.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let repo = UserDefaultsProviderSettingsRepository(userDefaults: defaults)
        repo.setEnabled(true, forProvider: "zai")
        if !zaiPath.isEmpty {
            repo.setZaiConfigPath(zaiPath)
        }
        if !glmEnvVar.isEmpty {
            repo.setGlmAuthEnvVar(glmEnvVar)
        }
        return repo
    }

    // MARK: - API Key Extraction Preference Tests

    @Test
    func `probe prefers API key from config file over environment variable`() async {
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor).locate(.any).willReturn("/usr/bin/claude")

        given(mockExecutor).execute(
            binary: .any,
            args: .any,
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willReturn(CLIResult(output: Self.sampleConfigWithKey, exitCode: 0))

        let mockNetwork = MockNetworkClient()
        let settings = makeSettingsRepository(glmEnvVar: "GLM_TOKEN")

        let probe = ZaiUsageProbe(cliExecutor: mockExecutor, networkClient: mockNetwork, settingsRepository: settings)

        let isAvailable = await probe.isAvailable()

        #expect(isAvailable == true)
    }

    @Test
    func `probe falls back to environment variable when config file has no API key`() async {
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor).locate(.any).willReturn("/usr/bin/claude")

        given(mockExecutor).execute(
            binary: .any,
            args: .any,
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willReturn(CLIResult(output: Self.sampleConfigWithoutKey, exitCode: 0))

        let mockNetwork = MockNetworkClient()
        let settings = makeSettingsRepository(glmEnvVar: "GLM_TOKEN")

        let probe = ZaiUsageProbe(cliExecutor: mockExecutor, networkClient: mockNetwork, settingsRepository: settings)

        let isAvailable = await probe.isAvailable()

        #expect(isAvailable == true)
    }

    @Test
    func `probe reports unavailable when no API key found in config or env var`() async {
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor).locate(.any).willReturn("/usr/bin/claude")

        given(mockExecutor).execute(
            binary: .any,
            args: .any,
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willReturn(CLIResult(output: Self.sampleConfigWithoutKey, exitCode: 0))

        let mockNetwork = MockNetworkClient()
        let settings = makeSettingsRepository(glmEnvVar: "")

        let probe = ZaiUsageProbe(cliExecutor: mockExecutor, networkClient: mockNetwork, settingsRepository: settings)

        // isAvailable only checks if Claude is installed and z.ai is configured
        // It doesn't validate the API key (that's probe's job)
        let isAvailable = await probe.isAvailable()
        #expect(isAvailable == true)

        // The actual probe() call should fail when trying to get the API key
        do {
            _ = try await probe.probe()
            #expect(Bool(false), "Expected probe() to throw authenticationRequired")
        } catch ProbeError.authenticationRequired {
            // Expected - no API key available
        } catch {
            #expect(Bool(false), "Expected authenticationRequired, got: \(error)")
        }
    }

    // MARK: - Login Shell Fallback Tests

    @Test
    func `probe resolves env var through login shell when missing from process environment`() async throws {
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor).locate(.any).willReturn("/usr/bin/claude")
        stubConfigRead(mockExecutor, config: Self.sampleConfigWithoutKey)
        stubLoginShell(mockExecutor, output: "shell-api-key")

        let mockNetwork = MockNetworkClient()
        given(mockNetwork).request(.any).willReturn((Data(Self.sampleQuotaResponse.utf8), makeOKResponse()))

        let uniqueVar = "CLAUDEBAR_TEST_GLM_\(UUID().uuidString.replacingOccurrences(of: "-", with: "_"))"
        let settings = makeSettingsRepository(glmEnvVar: uniqueVar)
        let probe = ZaiUsageProbe(cliExecutor: mockExecutor, networkClient: mockNetwork, settingsRepository: settings)

        let snapshot = try await probe.probe()

        #expect(snapshot.providerId == "zai")
        #expect(!snapshot.quotas.isEmpty)
    }

    @Test
    func `probe throws authenticationRequired when login shell also reports the variable empty`() async throws {
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor).locate(.any).willReturn("/usr/bin/claude")
        stubConfigRead(mockExecutor, config: Self.sampleConfigWithoutKey)
        stubLoginShell(mockExecutor, output: "")

        let mockNetwork = MockNetworkClient()
        let settings = makeSettingsRepository(glmEnvVar: "CLAUDEBAR_TEST_GLM_EMPTY")
        let probe = ZaiUsageProbe(cliExecutor: mockExecutor, networkClient: mockNetwork, settingsRepository: settings)

        await #expect(throws: ProbeError.authenticationRequired) {
            try await probe.probe()
        }
    }

    @Test
    func `probe throws authenticationRequired for invalid env var name without shell fallback`() async throws {
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor).locate(.any).willReturn("/usr/bin/claude")
        stubConfigRead(mockExecutor, config: Self.sampleConfigWithoutKey)
        stubLoginShell(mockExecutor, output: "shell-api-key")

        let mockNetwork = MockNetworkClient()
        let settings = makeSettingsRepository(glmEnvVar: "GLM TOKEN;rm -rf /")
        let probe = ZaiUsageProbe(cliExecutor: mockExecutor, networkClient: mockNetwork, settingsRepository: settings)

        await #expect(throws: ProbeError.authenticationRequired) {
            try await probe.probe()
        }
    }

    @Test
    func `probe prefers config file key even when env var and shell would provide one`() async throws {
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor).locate(.any).willReturn("/usr/bin/claude")
        stubConfigRead(mockExecutor, config: Self.sampleConfigWithKey)
        stubLoginShell(mockExecutor, output: "shell-api-key")

        let mockNetwork = MockNetworkClient()
        given(mockNetwork).request(.matching { request in
            request.value(forHTTPHeaderField: "Authorization") == "Bearer config-api-key"
        }).willReturn((Data(Self.sampleQuotaResponse.utf8), makeOKResponse()))

        let settings = makeSettingsRepository(glmEnvVar: "CLAUDEBAR_TEST_GLM_UNUSED")
        let probe = ZaiUsageProbe(cliExecutor: mockExecutor, networkClient: mockNetwork, settingsRepository: settings)

        let snapshot = try await probe.probe()

        #expect(snapshot.providerId == "zai")
    }

    // MARK: - Custom Config Path Tests

    @Test
    func `probe uses settings repository for path resolution`() async {
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor).locate(.any).willReturn("/usr/bin/claude")

        given(mockExecutor).execute(
            binary: .any,
            args: .any,
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willReturn(CLIResult(output: "", exitCode: 0))

        let mockNetwork = MockNetworkClient()
        let settings = makeSettingsRepository(
            zaiPath: "/custom/path/settings.json",
            glmEnvVar: ""
        )

        let probe = ZaiUsageProbe(cliExecutor: mockExecutor, networkClient: mockNetwork, settingsRepository: settings)

        _ = await probe.isAvailable()

        #expect(true)
    }
}
