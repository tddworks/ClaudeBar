import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

@Suite("KimiProvider Tests")
struct KimiProviderTests {

    /// Creates a mock settings repository that returns true for all providers
    private func makeSettingsRepository() -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(mock).isEnabled(forProvider: .any).willReturn(true)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        return mock
    }

    // MARK: - Identity Tests

    @Test
    func `kimi provider has correct id`() {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let kimi = KimiProvider(probe: mockProbe, settingsRepository: settings)

        #expect(kimi.id == "kimi")
    }

    @Test
    func `kimi provider has correct name`() {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let kimi = KimiProvider(probe: mockProbe, settingsRepository: settings)

        #expect(kimi.name == "Kimi")
    }

    @Test
    func `kimi provider has correct cliCommand`() {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let kimi = KimiProvider(probe: mockProbe, settingsRepository: settings)

        #expect(kimi.cliCommand == "kimi")
    }

    @Test
    func `kimi provider has dashboard URL`() {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let kimi = KimiProvider(probe: mockProbe, settingsRepository: settings)

        #expect(kimi.dashboardURL == URL(string: "https://www.kimi.com/code/console"))
    }

    @Test
    func `kimi provider has no status page URL`() {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let kimi = KimiProvider(probe: mockProbe, settingsRepository: settings)

        #expect(kimi.statusPageURL == nil)
    }

    @Test
    func `kimi provider is enabled by default`() {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let kimi = KimiProvider(probe: mockProbe, settingsRepository: settings)

        #expect(kimi.isEnabled == true)
    }

    // MARK: - State Tests

    @Test
    func `kimi provider starts with no snapshot`() {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let kimi = KimiProvider(probe: mockProbe, settingsRepository: settings)

        #expect(kimi.snapshot == nil)
    }

    @Test
    func `kimi provider starts not syncing`() {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let kimi = KimiProvider(probe: mockProbe, settingsRepository: settings)

        #expect(kimi.isSyncing == false)
    }

    @Test
    func `kimi provider starts with no error`() {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let kimi = KimiProvider(probe: mockProbe, settingsRepository: settings)

        #expect(kimi.lastError == nil)
    }

    // MARK: - Delegation Tests

    @Test
    func `kimi provider delegates isAvailable to probe`() async {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).isAvailable().willReturn(true)
        let kimi = KimiProvider(probe: mockProbe, settingsRepository: settings)

        let isAvailable = await kimi.isAvailable()

        #expect(isAvailable == true)
    }

    @Test
    func `kimi provider delegates isAvailable false to probe`() async {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).isAvailable().willReturn(false)
        let kimi = KimiProvider(probe: mockProbe, settingsRepository: settings)

        let isAvailable = await kimi.isAvailable()

        #expect(isAvailable == false)
    }

    @Test
    func `kimi provider delegates refresh to probe`() async throws {
        let settings = makeSettingsRepository()
        let expectedSnapshot = UsageSnapshot(
            providerId: "kimi",
            quotas: [UsageQuota(percentRemaining: 89.55, quotaType: .weekly, providerId: "kimi", resetText: "214/2048 requests")],
            capturedAt: Date()
        )
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(expectedSnapshot)
        let kimi = KimiProvider(probe: mockProbe, settingsRepository: settings)

        let snapshot = try await kimi.refresh()

        #expect(snapshot.providerId == "kimi")
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas.first?.percentRemaining == 89.55)
    }

    // MARK: - Snapshot Storage Tests

    @Test
    func `kimi provider stores snapshot after refresh`() async throws {
        let settings = makeSettingsRepository()
        let expectedSnapshot = UsageSnapshot(
            providerId: "kimi",
            quotas: [UsageQuota(percentRemaining: 80, quotaType: .weekly, providerId: "kimi")],
            capturedAt: Date()
        )
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(expectedSnapshot)
        let kimi = KimiProvider(probe: mockProbe, settingsRepository: settings)

        #expect(kimi.snapshot == nil)

        _ = try await kimi.refresh()

        #expect(kimi.snapshot != nil)
        #expect(kimi.snapshot?.quotas.first?.percentRemaining == 80)
    }

    @Test
    func `kimi provider clears error on successful refresh`() async throws {
        let settings = makeSettingsRepository()
        let failingProbe = MockUsageProbe()
        given(failingProbe).probe().willThrow(ProbeError.authenticationRequired)
        let kimiWithFailingProbe = KimiProvider(probe: failingProbe, settingsRepository: settings)

        do {
            _ = try await kimiWithFailingProbe.refresh()
        } catch {
            // Expected
        }
        #expect(kimiWithFailingProbe.lastError != nil)

        let succeedingProbe = MockUsageProbe()
        let snapshot = UsageSnapshot(providerId: "kimi", quotas: [], capturedAt: Date())
        given(succeedingProbe).probe().willReturn(snapshot)
        let kimiWithSucceedingProbe = KimiProvider(probe: succeedingProbe, settingsRepository: settings)

        _ = try await kimiWithSucceedingProbe.refresh()

        #expect(kimiWithSucceedingProbe.lastError == nil)
    }

    // MARK: - Error Handling Tests

    @Test
    func `kimi provider stores error on refresh failure`() async {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willThrow(ProbeError.authenticationRequired)
        let kimi = KimiProvider(probe: mockProbe, settingsRepository: settings)

        #expect(kimi.lastError == nil)

        do {
            _ = try await kimi.refresh()
        } catch {
            // Expected
        }

        #expect(kimi.lastError != nil)
    }

    @Test
    func `kimi provider rethrows probe errors`() async {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willThrow(ProbeError.authenticationRequired)
        let kimi = KimiProvider(probe: mockProbe, settingsRepository: settings)

        await #expect(throws: ProbeError.authenticationRequired) {
            try await kimi.refresh()
        }
    }

    // MARK: - Syncing State Tests

    @Test
    func `kimi provider resets isSyncing after refresh completes`() async throws {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(UsageSnapshot(
            providerId: "kimi",
            quotas: [],
            capturedAt: Date()
        ))
        let kimi = KimiProvider(probe: mockProbe, settingsRepository: settings)

        #expect(kimi.isSyncing == false)

        _ = try await kimi.refresh()

        #expect(kimi.isSyncing == false)
    }

    @Test
    func `kimi provider resets isSyncing after refresh fails`() async {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willThrow(ProbeError.timeout)
        let kimi = KimiProvider(probe: mockProbe, settingsRepository: settings)

        do {
            _ = try await kimi.refresh()
        } catch {
            // Expected
        }

        #expect(kimi.isSyncing == false)
    }
}
