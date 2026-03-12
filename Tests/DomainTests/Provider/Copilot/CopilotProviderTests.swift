import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

@Suite("CopilotProvider Tests")
struct CopilotProviderTests {

    // MARK: - Test Helper

    private func makeProvider(
        enabled: Bool = false,
        username: String = "",
        hasToken: Bool = false,
        probe: MockUsageProbe? = nil
    ) -> CopilotProvider {
        let settings = MockRepositoryFactory.makeCopilotSettingsRepository(
            enabled: enabled,
            username: username,
            hasToken: hasToken
        )
        let mockProbe = probe ?? MockUsageProbe()
        return CopilotProvider(probe: mockProbe, settingsRepository: settings)
    }

    // MARK: - Identity Tests

    @Test
    func `copilot provider has correct id`() {
        let copilot = makeProvider()
        #expect(copilot.id == "copilot")
    }

    @Test
    func `copilot provider has correct name`() {
        let copilot = makeProvider()
        #expect(copilot.name == "Copilot")
    }

    @Test
    func `copilot provider has correct cliCommand`() {
        let copilot = makeProvider()
        #expect(copilot.cliCommand == "gh")
    }

    @Test
    func `copilot provider has dashboard URL pointing to GitHub`() {
        let copilot = makeProvider()
        #expect(copilot.dashboardURL != nil)
        #expect(copilot.dashboardURL?.host?.contains("github") == true)
    }

    @Test
    func `copilot provider has status page URL`() {
        let copilot = makeProvider()
        #expect(copilot.statusPageURL != nil)
        #expect(copilot.statusPageURL?.host?.contains("githubstatus") == true)
    }

    @Test
    func `copilot provider is disabled by default`() {
        let copilot = makeProvider(enabled: false)
        #expect(copilot.isEnabled == false)
    }

    // MARK: - State Tests

    @Test
    func `copilot provider starts with no snapshot`() {
        let copilot = makeProvider()
        #expect(copilot.snapshot == nil)
    }

    @Test
    func `copilot provider starts not syncing`() {
        let copilot = makeProvider()
        #expect(copilot.isSyncing == false)
    }

    @Test
    func `copilot provider starts with no error`() {
        let copilot = makeProvider()
        #expect(copilot.lastError == nil)
    }

    // MARK: - Delegation Tests

    @Test
    func `copilot provider delegates isAvailable to probe`() async {
        let mockProbe = MockUsageProbe()
        given(mockProbe).isAvailable().willReturn(true)
        let copilot = makeProvider(probe: mockProbe)

        let isAvailable = await copilot.isAvailable()

        #expect(isAvailable == true)
    }

    @Test
    func `copilot provider delegates isAvailable false to probe`() async {
        let mockProbe = MockUsageProbe()
        given(mockProbe).isAvailable().willReturn(false)
        let copilot = makeProvider(probe: mockProbe)

        let isAvailable = await copilot.isAvailable()

        #expect(isAvailable == false)
    }

    @Test
    func `copilot provider delegates refresh to probe`() async throws {
        let expectedSnapshot = UsageSnapshot(
            providerId: "copilot",
            quotas: [UsageQuota(percentRemaining: 95, quotaType: .session, providerId: "copilot", resetText: "100/2000 requests")],
            capturedAt: Date()
        )
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(expectedSnapshot)
        let copilot = makeProvider(probe: mockProbe)

        let snapshot = try await copilot.refresh()

        #expect(snapshot.providerId == "copilot")
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas.first?.percentRemaining == 95)
    }

    // MARK: - Snapshot Storage Tests

    @Test
    func `copilot provider stores snapshot after refresh`() async throws {
        let expectedSnapshot = UsageSnapshot(
            providerId: "copilot",
            quotas: [UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "copilot")],
            capturedAt: Date()
        )
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(expectedSnapshot)
        let copilot = makeProvider(probe: mockProbe)

        #expect(copilot.snapshot == nil)

        _ = try await copilot.refresh()

        #expect(copilot.snapshot != nil)
        #expect(copilot.snapshot?.quotas.first?.percentRemaining == 80)
    }

    @Test
    func `copilot provider clears error on successful refresh`() async throws {
        // Use two separate probes to simulate the behavior
        let failingProbe = MockUsageProbe()
        given(failingProbe).probe().willThrow(ProbeError.timeout)
        let copilotWithFailingProbe = makeProvider(probe: failingProbe)

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
        let copilotWithSucceedingProbe = makeProvider(probe: succeedingProbe)

        _ = try await copilotWithSucceedingProbe.refresh()

        #expect(copilotWithSucceedingProbe.lastError == nil)
    }

    // MARK: - Error Handling Tests

    @Test
    func `copilot provider stores error on refresh failure`() async {
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willThrow(ProbeError.authenticationRequired)
        let copilot = makeProvider(probe: mockProbe)

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
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willThrow(ProbeError.authenticationRequired)
        let copilot = makeProvider(probe: mockProbe)

        await #expect(throws: ProbeError.authenticationRequired) {
            try await copilot.refresh()
        }
    }

    // MARK: - Syncing State Tests

    @Test
    func `copilot provider resets isSyncing after refresh completes`() async throws {
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(UsageSnapshot(
            providerId: "copilot",
            quotas: [],
            capturedAt: Date()
        ))
        let copilot = makeProvider(probe: mockProbe)

        #expect(copilot.isSyncing == false)

        _ = try await copilot.refresh()

        #expect(copilot.isSyncing == false)
    }

    @Test
    func `copilot provider resets isSyncing after refresh fails`() async {
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willThrow(ProbeError.timeout)
        let copilot = makeProvider(probe: mockProbe)

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
        let copilotSettings = MockRepositoryFactory.makeCopilotSettingsRepository()
        let baseSettings = MockRepositoryFactory.makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: copilotSettings)
        let claude = ClaudeProvider(probe: mockProbe, settingsRepository: baseSettings)
        let codex = CodexProvider(probe: mockProbe, settingsRepository: baseSettings)
        let gemini = GeminiProvider(probe: mockProbe, settingsRepository: baseSettings)

        let ids = Set([copilot.id, claude.id, codex.id, gemini.id])
        #expect(ids.count == 4) // All unique
    }

    // MARK: - Credential Management Tests

    @Test
    func `copilot provider loads username from settings`() {
        let copilot = makeProvider(username: "testuser")
        #expect(copilot.username == "testuser")
    }

    @Test
    func `copilot provider reports hasToken when token exists`() {
        let copilot = makeProvider(hasToken: true)
        #expect(copilot.hasToken == true)
    }

    @Test
    func `copilot provider reports hasToken when token does not exist`() {
        let copilot = makeProvider(hasToken: false)
        #expect(copilot.hasToken == false)
    }

    @Test
    func `copilot provider can save and retrieve token`() {
        let settings = MockRepositoryFactory.makeCopilotSettingsRepository()
        let mockProbe = MockUsageProbe()
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings)

        // Initially no token
        #expect(copilot.hasToken == false)

        // Save a token
        copilot.saveToken("ghp_test123")

        // Now has token and can retrieve it
        #expect(copilot.hasToken == true)
        #expect(copilot.getToken() == "ghp_test123")
    }

    @Test
    func `copilot provider clears username after deleting credentials`() {
        let settings = MockRepositoryFactory.makeCopilotSettingsRepository(username: "testuser", hasToken: true)
        let mockProbe = MockUsageProbe()
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings)

        // Initial username is loaded from repository
        #expect(copilot.username == "testuser")
        #expect(copilot.hasToken == true)

        // Delete credentials
        copilot.deleteCredentials()

        // Username is cleared
        #expect(copilot.username == "")
        #expect(copilot.hasToken == false)
    }

    // MARK: - Probe Mode Tests

    @Test
    func `copilot provider defaults to billing mode`() {
        let settings = MockRepositoryFactory.makeCopilotSettingsRepository()
        let mockProbe = MockUsageProbe()
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings)

        #expect(copilot.probeMode == .billing)
    }

    @Test
    func `copilot provider uses billing probe in billing mode`() async throws {
        let billingProbe = MockUsageProbe()
        let internalProbe = MockUsageProbe()
        let settings = MockRepositoryFactory.makeCopilotSettingsRepository()

        let billingSnapshot = UsageSnapshot(
            providerId: "copilot",
            quotas: [UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "copilot", resetText: "10/50 requests")],
            capturedAt: Date()
        )
        given(billingProbe).probe().willReturn(billingSnapshot)
        given(billingProbe).isAvailable().willReturn(true)

        let copilot = CopilotProvider(
            billingProbe: billingProbe,
            internalProbe: internalProbe,
            settingsRepository: settings
        )

        // Default is billing mode
        #expect(copilot.probeMode == .billing)

        let snapshot = try await copilot.refresh()
        #expect(snapshot.quotas.first?.resetText == "10/50 requests")
    }

    @Test
    func `copilot provider uses internal probe in copilotAPI mode`() async throws {
        let billingProbe = MockUsageProbe()
        let internalProbe = MockUsageProbe()
        let settings = MockRepositoryFactory.makeCopilotSettingsRepository()
        settings.setCopilotProbeMode(.copilotAPI)

        let internalSnapshot = UsageSnapshot(
            providerId: "copilot",
            quotas: [UsageQuota(percentRemaining: 99.3, quotaType: .session, providerId: "copilot", resetText: "2/300 requests")],
            capturedAt: Date()
        )
        given(internalProbe).probe().willReturn(internalSnapshot)
        given(internalProbe).isAvailable().willReturn(true)

        let copilot = CopilotProvider(
            billingProbe: billingProbe,
            internalProbe: internalProbe,
            settingsRepository: settings
        )

        #expect(copilot.probeMode == .copilotAPI)

        let snapshot = try await copilot.refresh()
        #expect(snapshot.quotas.first?.resetText == "2/300 requests")
    }

    @Test
    func `copilot provider falls back to billing when internal probe is nil`() async throws {
        let billingProbe = MockUsageProbe()
        let settings = MockRepositoryFactory.makeCopilotSettingsRepository()
        settings.setCopilotProbeMode(.copilotAPI)

        let billingSnapshot = UsageSnapshot(
            providerId: "copilot",
            quotas: [UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "copilot", resetText: "10/50 requests")],
            capturedAt: Date()
        )
        given(billingProbe).probe().willReturn(billingSnapshot)
        given(billingProbe).isAvailable().willReturn(true)

        // Use single probe init (no internal probe)
        let copilot = CopilotProvider(probe: billingProbe, settingsRepository: settings)

        // Mode is copilotAPI but internal probe is nil, should fall back to billing
        #expect(copilot.probeMode == .copilotAPI)

        let snapshot = try await copilot.refresh()
        #expect(snapshot.quotas.first?.resetText == "10/50 requests")
    }

    @Test
    func `copilot provider supportsInternalApiMode when internal probe provided`() {
        let billingProbe = MockUsageProbe()
        let internalProbe = MockUsageProbe()
        let settings = MockRepositoryFactory.makeCopilotSettingsRepository()

        let copilotWithInternal = CopilotProvider(
            billingProbe: billingProbe,
            internalProbe: internalProbe,
            settingsRepository: settings
        )
        #expect(copilotWithInternal.supportsInternalApiMode == true)

        let copilotWithoutInternal = CopilotProvider(
            probe: billingProbe,
            settingsRepository: settings
        )
        #expect(copilotWithoutInternal.supportsInternalApiMode == false)
    }
}
