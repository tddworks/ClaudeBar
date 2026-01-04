import Testing
import Foundation
import Mockable
@testable import Domain

@Suite("CopilotProvider Env Var Configuration Tests")
struct CopilotProviderEnvVarConfigTests {

    // MARK: - Configuration Injection Tests

    @Test
    func `copilot provider initializes with default configuration`() {
        // Given: standard repositories with default config
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let credentials = MockRepositoryFactory.makeCredentialRepository()
        let config = MockRepositoryFactory.makeConfigRepository()
        let mockProbe = MockUsageProbe()

        // When: creating a provider with default config
        let provider = CopilotProvider(
            probe: mockProbe,
            settingsRepository: settings,
            credentialRepository: credentials,
            configRepository: config
        )

        // Then: provider initializes with correct identity
        #expect(provider.id == "copilot")
        #expect(provider.name == "Copilot")
        #expect(provider.cliCommand == "gh")
    }

    @Test
    func `copilot provider initializes with custom copilot auth env var`() {
        // Given: config repository configured with custom env var
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let credentials = MockRepositoryFactory.makeCredentialRepository()
        let config = MockRepositoryFactory.makeConfigRepository(copilotAuthEnvVar: "CUSTOM_GH_TOKEN")
        let mockProbe = MockUsageProbe()

        // When: creating a provider with custom config
        let provider = CopilotProvider(
            probe: mockProbe,
            settingsRepository: settings,
            credentialRepository: credentials,
            configRepository: config
        )

        // Then: provider is created and configured
        #expect(provider.id == "copilot")
        #expect(provider.name == "Copilot")
    }

    // MARK: - Repository Injection Tests

    @Test
    func `copilot provider can be created with different config repositories`() {
        // Given: multiple different config repositories
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let credentials = MockRepositoryFactory.makeCredentialRepository()
        let configA = MockRepositoryFactory.makeConfigRepository(copilotAuthEnvVar: "ENV_VAR_A")
        let configB = MockRepositoryFactory.makeConfigRepository(copilotAuthEnvVar: "ENV_VAR_B")
        let mockProbe = MockUsageProbe()

        // When: creating providers with different configs
        let providerA = CopilotProvider(
            probe: mockProbe,
            settingsRepository: settings,
            credentialRepository: credentials,
            configRepository: configA
        )
        let providerB = CopilotProvider(
            probe: mockProbe,
            settingsRepository: settings,
            credentialRepository: credentials,
            configRepository: configB
        )

        // Then: both providers have identical identity (config doesn't affect id)
        #expect(providerA.id == providerB.id)
        #expect(providerA.name == providerB.name)
    }

    // MARK: - Initial State Tests

    @Test
    func `copilot provider initializes with no snapshot`() {
        // Given: default setup
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let credentials = MockRepositoryFactory.makeCredentialRepository()
        let config = MockRepositoryFactory.makeConfigRepository()
        let mockProbe = MockUsageProbe()

        // When: creating a provider
        let provider = CopilotProvider(
            probe: mockProbe,
            settingsRepository: settings,
            credentialRepository: credentials,
            configRepository: config
        )

        // Then: provider has not yet fetched any data
        #expect(provider.snapshot == nil)
        #expect(provider.isSyncing == false)
        #expect(provider.lastError == nil)
    }

    @Test
    func `copilot provider initializes with disabled status by default`() {
        // Given: settings repository that returns false for copilot
        let settings = MockRepositoryFactory.makeSettingsRepository(enabled: false)
        let credentials = MockRepositoryFactory.makeCredentialRepository()
        let config = MockRepositoryFactory.makeConfigRepository()
        let mockProbe = MockUsageProbe()

        // When: creating a provider
        let provider = CopilotProvider(
            probe: mockProbe,
            settingsRepository: settings,
            credentialRepository: credentials,
            configRepository: config
        )

        // Then: provider respects the disabled state from repository
        #expect(provider.isEnabled == false)
    }
}
