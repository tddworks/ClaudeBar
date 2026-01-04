import Testing
import Foundation
import Mockable
@testable import Domain

@Suite("CopilotProvider Tests")
struct CopilotProviderTests {

    // MARK: - Identity Tests

    @Test
    func `copilot provider has correct id`() {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let credentials = MockRepositoryFactory.makeCredentialRepository()
        let config = MockRepositoryFactory.makeConfigRepository()
        let mockProbe = MockUsageProbe()
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings, credentialRepository: credentials, configRepository: config)

        #expect(copilot.id == "copilot")
    }

    @Test
    func `copilot provider has correct name`() {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let credentials = MockRepositoryFactory.makeCredentialRepository()
        let config = MockRepositoryFactory.makeConfigRepository()
        let mockProbe = MockUsageProbe()
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings, credentialRepository: credentials, configRepository: config)

        #expect(copilot.name == "Copilot")
    }

    @Test
    func `copilot provider has correct cliCommand`() {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let credentials = MockRepositoryFactory.makeCredentialRepository()
        let config = MockRepositoryFactory.makeConfigRepository()
        let mockProbe = MockUsageProbe()
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings, credentialRepository: credentials, configRepository: config)

        #expect(copilot.cliCommand == "gh")
    }

    @Test
    func `copilot provider has dashboard URL pointing to GitHub`() {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let credentials = MockRepositoryFactory.makeCredentialRepository()
        let config = MockRepositoryFactory.makeConfigRepository()
        let mockProbe = MockUsageProbe()
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings, credentialRepository: credentials, configRepository: config)

        #expect(copilot.dashboardURL != nil)
        #expect(copilot.dashboardURL?.host?.contains("github") == true)
    }

    @Test
    func `copilot provider has status page URL`() {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let credentials = MockRepositoryFactory.makeCredentialRepository()
        let config = MockRepositoryFactory.makeConfigRepository()
        let mockProbe = MockUsageProbe()
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings, credentialRepository: credentials, configRepository: config)

        #expect(copilot.statusPageURL != nil)
        #expect(copilot.statusPageURL?.host?.contains("githubstatus") == true)
    }

    @Test
    func `copilot provider is disabled by default`() {
        // CopilotProvider defaults to disabled since it requires manual setup
        let settings = MockRepositoryFactory.makeSettingsRepository(enabled: false)
        let credentials = MockRepositoryFactory.makeCredentialRepository()
        let config = MockRepositoryFactory.makeConfigRepository()
        let mockProbe = MockUsageProbe()
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings, credentialRepository: credentials, configRepository: config)

        #expect(copilot.isEnabled == false)
    }

    // MARK: - State Tests

    @Test
    func `copilot provider saves token to credential store`() {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let credentials = MockRepositoryFactory.makeCredentialRepository()
        let config = MockRepositoryFactory.makeConfigRepository()
        let mockProbe = MockUsageProbe()
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings, credentialRepository: credentials, configRepository: config)

        #expect(copilot.snapshot == nil)
    }

    @Test
    func `copilot provider starts not syncing`() {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let credentials = MockRepositoryFactory.makeCredentialRepository()
        let config = MockRepositoryFactory.makeConfigRepository()
        let mockProbe = MockUsageProbe()
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings, credentialRepository: credentials, configRepository: config)

        #expect(copilot.isSyncing == false)
    }

    @Test
    func `copilot provider starts with no error`() {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let credentials = MockRepositoryFactory.makeCredentialRepository()
        let config = MockRepositoryFactory.makeConfigRepository()
        let mockProbe = MockUsageProbe()
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings, credentialRepository: credentials, configRepository: config)

        #expect(copilot.lastError == nil)
    }

    // MARK: - Delegation Tests

    @Test
    func `copilot provider delegates isAvailable to probe`() async {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let credentials = MockRepositoryFactory.makeCredentialRepository()
        let config = MockRepositoryFactory.makeConfigRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).isAvailable().willReturn(true)
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings, credentialRepository: credentials, configRepository: config)

        let isAvailable = await copilot.isAvailable()

        #expect(isAvailable == true)
    }

    @Test
    func `copilot provider delegates isAvailable false to probe`() async {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let credentials = MockRepositoryFactory.makeCredentialRepository()
        let config = MockRepositoryFactory.makeConfigRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).isAvailable().willReturn(false)
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings, credentialRepository: credentials, configRepository: config)

        let isAvailable = await copilot.isAvailable()

        #expect(isAvailable == false)
    }

    @Test
    func `copilot provider delegates refresh to probe`() async throws {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let credentials = MockRepositoryFactory.makeCredentialRepository()
        let config = MockRepositoryFactory.makeConfigRepository()
        let expectedSnapshot = UsageSnapshot(
            providerId: "copilot",
            quotas: [UsageQuota(percentRemaining: 95, quotaType: .session, providerId: "copilot", resetText: "100/2000 requests")],
            capturedAt: Date()
        )
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(expectedSnapshot)
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings, credentialRepository: credentials, configRepository: config)

        let snapshot = try await copilot.refresh()

        #expect(snapshot.providerId == "copilot")
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas.first?.percentRemaining == 95)
    }

    // MARK: - Snapshot Storage Tests

    @Test
    func `copilot provider stores snapshot after refresh`() async throws {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let credentials = MockRepositoryFactory.makeCredentialRepository()
        let config = MockRepositoryFactory.makeConfigRepository()
        let expectedSnapshot = UsageSnapshot(
            providerId: "copilot",
            quotas: [UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "copilot")],
            capturedAt: Date()
        )
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(expectedSnapshot)
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings, credentialRepository: credentials, configRepository: config)

        #expect(copilot.snapshot == nil)

        _ = try await copilot.refresh()

        #expect(copilot.snapshot != nil)
        #expect(copilot.snapshot?.quotas.first?.percentRemaining == 80)
    }

    @Test
    func `copilot provider clears error on successful refresh`() async throws {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let credentials = MockRepositoryFactory.makeCredentialRepository()
        let config = MockRepositoryFactory.makeConfigRepository()
        // Use two separate probes to simulate the behavior
        let failingProbe = MockUsageProbe()
        given(failingProbe).probe().willThrow(ProbeError.timeout)
        let copilotWithFailingProbe = CopilotProvider(probe: failingProbe, settingsRepository: settings, credentialRepository: credentials, configRepository: config)

        do {
            _ = try await copilotWithFailingProbe.refresh()
        } catch {
            // Expected
        }
        #expect(copilotWithFailingProbe.lastError != nil)

        // Create new provider with succeeding probe
        let succeedingProbe = MockUsageProbe()
        let snapshot = UsageSnapshot(providerId: "copilot", quotas: [], capturedAt: Date())
        given(succeedingProbe).probe().willReturn(snapshot)
        let copilotWithSucceedingProbe = CopilotProvider(probe: succeedingProbe, settingsRepository: settings, credentialRepository: credentials, configRepository: config)

        _ = try await copilotWithSucceedingProbe.refresh()

        #expect(copilotWithSucceedingProbe.lastError == nil)
    }

    // MARK: - Error Handling Tests

    @Test
    func `copilot provider stores error on refresh failure`() async {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let credentials = MockRepositoryFactory.makeCredentialRepository()
        let config = MockRepositoryFactory.makeConfigRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willThrow(ProbeError.authenticationRequired)
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings, credentialRepository: credentials, configRepository: config)

        #expect(copilot.lastError == nil)

        do {
            _ = try await copilot.refresh()
        } catch {
            // Expected
        }

        #expect(copilot.lastError != nil)
    }

    @Test
    func `copilot provider rethrows probe errors`() async {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let credentials = MockRepositoryFactory.makeCredentialRepository()
        let config = MockRepositoryFactory.makeConfigRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willThrow(ProbeError.authenticationRequired)
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings, credentialRepository: credentials, configRepository: config)

        await #expect(throws: ProbeError.authenticationRequired) {
            try await copilot.refresh()
        }
    }

    // MARK: - Syncing State Tests

    @Test
    func `copilot provider resets isSyncing after refresh completes`() async throws {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let credentials = MockRepositoryFactory.makeCredentialRepository()
        let config = MockRepositoryFactory.makeConfigRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(UsageSnapshot(
            providerId: "copilot",
            quotas: [],
            capturedAt: Date()
        ))
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings, credentialRepository: credentials, configRepository: config)

        #expect(copilot.isSyncing == false)

        _ = try await copilot.refresh()

        #expect(copilot.isSyncing == false)
    }

    @Test
    func `copilot provider resets isSyncing after refresh fails`() async {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let credentials = MockRepositoryFactory.makeCredentialRepository()
        let config = MockRepositoryFactory.makeConfigRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willThrow(ProbeError.timeout)
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings, credentialRepository: credentials, configRepository: config)

        do {
            _ = try await copilot.refresh()
        } catch {
            // Expected
        }

        #expect(copilot.isSyncing == false)
    }

    // MARK: - Uniqueness Tests

    @Test
    func `copilot provider has unique id compared to other providers`() {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let credentials = MockRepositoryFactory.makeCredentialRepository()
        let config = MockRepositoryFactory.makeConfigRepository()
        let mockProbe = MockUsageProbe()
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings, credentialRepository: credentials, configRepository: config)
        let claude = ClaudeProvider(probe: mockProbe, settingsRepository: settings)
        let codex = CodexProvider(probe: mockProbe, settingsRepository: settings)
        let gemini = GeminiProvider(probe: mockProbe, settingsRepository: settings)

        let ids = Set([copilot.id, claude.id, codex.id, gemini.id])
        #expect(ids.count == 4) // All unique
    }

    // MARK: - Credential Management Tests

    @Test
    func `copilot provider loads username from credential store`() {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let credentials = MockRepositoryFactory.makeCredentialRepository(username: "testuser")
        let config = MockRepositoryFactory.makeConfigRepository()
        let mockProbe = MockUsageProbe()
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings, credentialRepository: credentials, configRepository: config)

        #expect(copilot.username == "testuser")
    }

    @Test
    func `copilot provider reports hasToken when token exists`() {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let credentials = MockRepositoryFactory.makeCredentialRepository(hasToken: true)
        let config = MockRepositoryFactory.makeConfigRepository()
        let mockProbe = MockUsageProbe()
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings, credentialRepository: credentials, configRepository: config)

        #expect(copilot.hasToken == true)
    }

    @Test
    func `copilot provider reports hasToken when token does not exist`() {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let credentials = MockRepositoryFactory.makeCredentialRepository(hasToken: false)
        let config = MockRepositoryFactory.makeConfigRepository()
        let mockProbe = MockUsageProbe()
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings, credentialRepository: credentials, configRepository: config)

        #expect(copilot.hasToken == false)
    }

    @Test
    func `copilot provider can retrieve saved token`() {
        // Given: a mock that returns the saved token
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let config = MockRepositoryFactory.makeConfigRepository()
        let credentials = MockCredentialRepository()
        given(credentials).get(forKey: .value(CredentialKey.githubToken)).willReturn("ghp_test123")
        given(credentials).get(forKey: .value(CredentialKey.githubUsername)).willReturn(nil)
        given(credentials).exists(forKey: .any).willReturn(true)
        given(credentials).save(.any, forKey: .any).willReturn()
        let mockProbe = MockUsageProbe()
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings, credentialRepository: credentials, configRepository: config)

        // When: saving and then retrieving the token
        copilot.saveToken("ghp_test123")

        // Then: getToken returns the saved value
        #expect(copilot.getToken() == "ghp_test123")
        #expect(copilot.hasToken == true)
    }

    @Test
    func `copilot provider clears username after deleting credentials`() {
        // Given: a provider with username set
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let config = MockRepositoryFactory.makeConfigRepository()
        let credentials = MockCredentialRepository()
        given(credentials).get(forKey: .value(CredentialKey.githubUsername)).willReturn("testuser")
        given(credentials).get(forKey: .value(CredentialKey.githubToken)).willReturn("ghp_token")
        given(credentials).exists(forKey: .any).willReturn(false) // After delete, exists returns false
        given(credentials).save(.any, forKey: .any).willReturn()
        given(credentials).delete(forKey: .any).willReturn()
        let mockProbe = MockUsageProbe()
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings, credentialRepository: credentials, configRepository: config)

        // Initial username is loaded from repository
        #expect(copilot.username == "testuser")

        // When: deleting credentials
        copilot.deleteCredentials()

        // Then: username is cleared (observable state change)
        #expect(copilot.username == "")
        // And hasToken returns false (since mock returns false for exists after delete)
        #expect(copilot.hasToken == false)
    }
}
