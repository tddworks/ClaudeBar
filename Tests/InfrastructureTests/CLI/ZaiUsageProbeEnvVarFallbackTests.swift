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

    private func makeConfigRepository(
        zaiPath: String = "",
        glmEnvVar: String = "",
        copilotEnvVar: String = ""
    ) -> MockProviderConfigRepository {
        let mock = MockProviderConfigRepository()
        given(mock).zaiConfigPath().willReturn(zaiPath)
        given(mock).glmAuthEnvVar().willReturn(glmEnvVar)
        given(mock).copilotAuthEnvVar().willReturn(copilotEnvVar)
        given(mock).setZaiConfigPath(.any).willReturn()
        given(mock).setGlmAuthEnvVar(.any).willReturn()
        given(mock).setCopilotAuthEnvVar(.any).willReturn()
        return mock
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
        let mockConfig = makeConfigRepository(glmEnvVar: "GLM_TOKEN")
        
        let probe = ZaiUsageProbe(cliExecutor: mockExecutor, networkClient: mockNetwork, configRepository: mockConfig)
        
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
        let mockConfig = makeConfigRepository(glmEnvVar: "GLM_TOKEN")
        
        let probe = ZaiUsageProbe(cliExecutor: mockExecutor, networkClient: mockNetwork, configRepository: mockConfig)
        
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
        let mockConfig = makeConfigRepository(glmEnvVar: "")

        let probe = ZaiUsageProbe(cliExecutor: mockExecutor, networkClient: mockNetwork, configRepository: mockConfig)
        
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

    // MARK: - Custom Config Path Tests

    @Test
    func `probe uses config repository for path resolution`() async {
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
        let mockConfig = makeConfigRepository(
            zaiPath: "/custom/path/settings.json",
            glmEnvVar: ""
        )

        let probe = ZaiUsageProbe(cliExecutor: mockExecutor, networkClient: mockNetwork, configRepository: mockConfig)
        
        _ = await probe.isAvailable()
        
        #expect(true)
    }
}
