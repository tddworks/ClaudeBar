import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

@Suite("ZaiProvider Tests")
struct ZaiProviderTests {

    // MARK: - Identity Tests

    @Test
    func `zai provider has correct id`() {
        let settings = MockRepositoryFactory.makeZaiSettingsRepository()
        let mockProbe = MockUsageProbe()
        let zai = ZaiProvider(probe: mockProbe, settingsRepository: settings)

        #expect(zai.id == "zai")
    }

    @Test
    func `zai provider has correct name`() {
        let settings = MockRepositoryFactory.makeZaiSettingsRepository()
        let mockProbe = MockUsageProbe()
        let zai = ZaiProvider(probe: mockProbe, settingsRepository: settings)

        #expect(zai.name == "Z.ai")
    }

    @Test
    func `zai provider has correct cliCommand`() {
        let settings = MockRepositoryFactory.makeZaiSettingsRepository()
        let mockProbe = MockUsageProbe()
        let zai = ZaiProvider(probe: mockProbe, settingsRepository: settings)

        #expect(zai.cliCommand == "claude")
    }

    @Test
    func `zai provider has dashboard URL pointing to z.ai`() {
        let settings = MockRepositoryFactory.makeZaiSettingsRepository()
        let mockProbe = MockUsageProbe()
        let zai = ZaiProvider(probe: mockProbe, settingsRepository: settings)

        #expect(zai.dashboardURL != nil)
        #expect(zai.dashboardURL?.host?.contains("z.ai") == true)
    }

    @Test
    func `zai provider has status page URL`() {
        let settings = MockRepositoryFactory.makeZaiSettingsRepository()
        let mockProbe = MockUsageProbe()
        let zai = ZaiProvider(probe: mockProbe, settingsRepository: settings)

        #expect(zai.statusPageURL != nil)
        #expect(zai.statusPageURL?.host?.contains("z.ai") == true)
    }

    @Test
    func `zai provider is enabled by default`() {
        let settings = MockRepositoryFactory.makeZaiSettingsRepository()
        let mockProbe = MockUsageProbe()
        let zai = ZaiProvider(probe: mockProbe, settingsRepository: settings)

        #expect(zai.isEnabled == true)
    }

    // MARK: - State Tests

    @Test
    func `zai provider starts with no snapshot`() {
        let settings = MockRepositoryFactory.makeZaiSettingsRepository()
        let mockProbe = MockUsageProbe()
        let zai = ZaiProvider(probe: mockProbe, settingsRepository: settings)

        #expect(zai.snapshot == nil)
    }

    @Test
    func `zai provider starts not syncing`() {
        let settings = MockRepositoryFactory.makeZaiSettingsRepository()
        let mockProbe = MockUsageProbe()
        let zai = ZaiProvider(probe: mockProbe, settingsRepository: settings)

        #expect(zai.isSyncing == false)
    }

    @Test
    func `zai provider starts with no error`() {
        let settings = MockRepositoryFactory.makeZaiSettingsRepository()
        let mockProbe = MockUsageProbe()
        let zai = ZaiProvider(probe: mockProbe, settingsRepository: settings)

        #expect(zai.lastError == nil)
    }

    // MARK: - Delegation Tests

    @Test
    func `zai provider delegates isAvailable to probe`() async {
        let settings = MockRepositoryFactory.makeZaiSettingsRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).isAvailable().willReturn(true)
        let zai = ZaiProvider(probe: mockProbe, settingsRepository: settings)

        let isAvailable = await zai.isAvailable()

        #expect(isAvailable == true)
    }

    @Test
    func `zai provider delegates isAvailable false to probe`() async {
        let settings = MockRepositoryFactory.makeZaiSettingsRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).isAvailable().willReturn(false)
        let zai = ZaiProvider(probe: mockProbe, settingsRepository: settings)

        let isAvailable = await zai.isAvailable()

        #expect(isAvailable == false)
    }

    @Test
    func `zai provider delegates refresh to probe`() async throws {
        let settings = MockRepositoryFactory.makeZaiSettingsRepository()
        let expectedSnapshot = UsageSnapshot(
            providerId: "zai",
            quotas: [UsageQuota(percentRemaining: 95, quotaType: .session, providerId: "zai", resetText: "Resets in 1 hour")],
            capturedAt: Date()
        )
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(expectedSnapshot)
        let zai = ZaiProvider(probe: mockProbe, settingsRepository: settings)

        let snapshot = try await zai.refresh()

        #expect(snapshot.providerId == "zai")
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas.first?.percentRemaining == 95)
    }

    // MARK: - Snapshot Storage Tests

    @Test
    func `zai provider stores snapshot after refresh`() async throws {
        let settings = MockRepositoryFactory.makeZaiSettingsRepository()
        let expectedSnapshot = UsageSnapshot(
            providerId: "zai",
            quotas: [UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "zai")],
            capturedAt: Date()
        )
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(expectedSnapshot)
        let zai = ZaiProvider(probe: mockProbe, settingsRepository: settings)

        #expect(zai.snapshot == nil)

        _ = try await zai.refresh()

        #expect(zai.snapshot != nil)
        #expect(zai.snapshot?.quotas.first?.percentRemaining == 80)
    }

    @Test
    func `zai provider clears error on successful refresh`() async throws {
        let settings = MockRepositoryFactory.makeZaiSettingsRepository()
        // Use two separate probes to simulate the behavior
        let failingProbe = MockUsageProbe()
        given(failingProbe).probe().willThrow(ProbeError.timeout)
        let zaiWithFailingProbe = ZaiProvider(probe: failingProbe, settingsRepository: settings)

        do {
            _ = try await zaiWithFailingProbe.refresh()
        } catch {
            // Expected
        }
        #expect(zaiWithFailingProbe.lastError != nil)

        // Create new provider with succeeding probe
        let succeedingProbe = MockUsageProbe()
        let snapshot = UsageSnapshot(providerId: "zai", quotas: [], capturedAt: Date())
        given(succeedingProbe).probe().willReturn(snapshot)
        let zaiWithSucceedingProbe = ZaiProvider(probe: succeedingProbe, settingsRepository: settings)

        _ = try await zaiWithSucceedingProbe.refresh()

        #expect(zaiWithSucceedingProbe.lastError == nil)
    }

    // MARK: - Error Handling Tests

    @Test
    func `zai provider stores error on refresh failure`() async {
        let settings = MockRepositoryFactory.makeZaiSettingsRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willThrow(ProbeError.executionFailed("Connection failed"))
        let zai = ZaiProvider(probe: mockProbe, settingsRepository: settings)

        #expect(zai.lastError == nil)

        do {
            _ = try await zai.refresh()
        } catch {
            // Expected
        }

        #expect(zai.lastError != nil)
    }

    @Test
    func `zai provider rethrows probe errors`() async {
        let settings = MockRepositoryFactory.makeZaiSettingsRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willThrow(ProbeError.executionFailed("API error"))
        let zai = ZaiProvider(probe: mockProbe, settingsRepository: settings)

        await #expect(throws: ProbeError.executionFailed("API error")) {
            try await zai.refresh()
        }
    }

    // MARK: - Syncing State Tests

    @Test
    func `zai provider resets isSyncing after refresh completes`() async throws {
        let settings = MockRepositoryFactory.makeZaiSettingsRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(UsageSnapshot(
            providerId: "zai",
            quotas: [],
            capturedAt: Date()
        ))
        let zai = ZaiProvider(probe: mockProbe, settingsRepository: settings)

        #expect(zai.isSyncing == false)

        _ = try await zai.refresh()

        #expect(zai.isSyncing == false)
    }

    @Test
    func `zai provider resets isSyncing after refresh fails`() async {
        let settings = MockRepositoryFactory.makeZaiSettingsRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willThrow(ProbeError.timeout)
        let zai = ZaiProvider(probe: mockProbe, settingsRepository: settings)

        do {
            _ = try await zai.refresh()
        } catch {
            // Expected
        }

        #expect(zai.isSyncing == false)
    }

    // MARK: - Uniqueness Tests

    @Test
    func `zai provider has unique id compared to other providers`() {
        let zaiSettings = MockRepositoryFactory.makeZaiSettingsRepository()
        let copilotSettings = MockRepositoryFactory.makeCopilotSettingsRepository()
        let baseSettings = MockRepositoryFactory.makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let zai = ZaiProvider(probe: mockProbe, settingsRepository: zaiSettings)
        let claude = ClaudeProvider(probe: mockProbe, settingsRepository: baseSettings)
        let codex = CodexProvider(probe: mockProbe, settingsRepository: baseSettings)
        let gemini = GeminiProvider(probe: mockProbe, settingsRepository: baseSettings)
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: copilotSettings)
        let antigravity = AntigravityProvider(probe: mockProbe, settingsRepository: baseSettings)

        let ids = Set([zai.id, claude.id, codex.id, gemini.id, copilot.id, antigravity.id])
        #expect(ids.count == 6) // All unique
    }
}
