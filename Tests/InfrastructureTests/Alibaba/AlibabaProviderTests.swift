import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

@Suite
@MainActor
struct AlibabaProviderTests {

    private func makeSettingsRepository() -> UserDefaultsProviderSettingsRepository {
        let suiteName = "com.claudebar.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return UserDefaultsProviderSettingsRepository(userDefaults: defaults)
    }

    // MARK: - Identity

    @Test
    func `provider has correct identity`() {
        let mockProbe = MockUsageProbe()
        let repo = makeSettingsRepository()
        let provider = AlibabaProvider(probe: mockProbe, settingsRepository: repo)

        #expect(provider.id == "alibaba")
        #expect(provider.name == "Alibaba")
        #expect(provider.cliCommand == "alibaba-coding-plan")
        #expect(provider.dashboardURL != nil)
        #expect(provider.dashboardURL?.absoluteString.contains("modelstudio") == true)
    }

    // MARK: - Default State

    @Test
    func `provider defaults to disabled`() {
        let mockProbe = MockUsageProbe()
        let repo = makeSettingsRepository()
        let provider = AlibabaProvider(probe: mockProbe, settingsRepository: repo)

        #expect(provider.isEnabled == false)
    }

    @Test
    func `provider reflects persisted enabled state`() {
        let mockProbe = MockUsageProbe()
        let repo = makeSettingsRepository()
        repo.setEnabled(true, forProvider: "alibaba")
        let provider = AlibabaProvider(probe: mockProbe, settingsRepository: repo)

        #expect(provider.isEnabled == true)
    }

    @Test
    func `provider starts with nil snapshot and no error`() {
        let mockProbe = MockUsageProbe()
        let repo = makeSettingsRepository()
        let provider = AlibabaProvider(probe: mockProbe, settingsRepository: repo)

        #expect(provider.snapshot == nil)
        #expect(provider.lastError == nil)
        #expect(provider.isSyncing == false)
    }

    // MARK: - isEnabled Persistence

    @Test
    func `setting isEnabled persists to repository`() {
        let mockProbe = MockUsageProbe()
        let repo = makeSettingsRepository()
        let provider = AlibabaProvider(probe: mockProbe, settingsRepository: repo)

        provider.isEnabled = true
        #expect(repo.isEnabled(forProvider: "alibaba") == true)

        provider.isEnabled = false
        #expect(repo.isEnabled(forProvider: "alibaba") == false)
    }

    // MARK: - isAvailable

    @Test
    func `isAvailable delegates to probe`() async {
        let mockProbe = MockUsageProbe()
        given(mockProbe).isAvailable().willReturn(true)
        let repo = makeSettingsRepository()
        let provider = AlibabaProvider(probe: mockProbe, settingsRepository: repo)

        let available = await provider.isAvailable()
        #expect(available == true)
    }

    @Test
    func `isAvailable returns false when probe unavailable`() async {
        let mockProbe = MockUsageProbe()
        given(mockProbe).isAvailable().willReturn(false)
        let repo = makeSettingsRepository()
        let provider = AlibabaProvider(probe: mockProbe, settingsRepository: repo)

        let available = await provider.isAvailable()
        #expect(available == false)
    }

    // MARK: - Refresh

    @Test
    func `refresh updates snapshot on success`() async throws {
        let mockProbe = MockUsageProbe()
        let expectedSnapshot = UsageSnapshot(
            providerId: "alibaba",
            quotas: [UsageQuota(percentRemaining: 90.0, quotaType: .session, providerId: "alibaba")],
            capturedAt: Date()
        )
        given(mockProbe).probe().willReturn(expectedSnapshot)

        let repo = makeSettingsRepository()
        let provider = AlibabaProvider(probe: mockProbe, settingsRepository: repo)

        let result = try await provider.refresh()
        #expect(result.providerId == "alibaba")
        #expect(provider.snapshot?.quotas.count == 1)
        #expect(provider.lastError == nil)
    }

    @Test
    func `refresh stores error on failure`() async {
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willThrow(ProbeError.authenticationRequired)

        let repo = makeSettingsRepository()
        let provider = AlibabaProvider(probe: mockProbe, settingsRepository: repo)

        do {
            _ = try await provider.refresh()
            Issue.record("Expected error")
        } catch {
            #expect(provider.lastError != nil)
            #expect(provider.snapshot == nil)
        }
    }

    @Test
    func `successful refresh clears previous error`() async throws {
        let repo = makeSettingsRepository()

        // Use two separate probes to simulate the behavior
        let failingProbe = MockUsageProbe()
        given(failingProbe).probe().willThrow(ProbeError.authenticationRequired)
        let alibabWithFailingProbe = AlibabaProvider(probe: failingProbe, settingsRepository: repo)

        do {
            _ = try await alibabWithFailingProbe.refresh()
        } catch {
            // Expected
        }
        #expect(alibabWithFailingProbe.lastError != nil)

        // Create new provider with succeeding probe
        let succeedingProbe = MockUsageProbe()
        let snapshot = UsageSnapshot(providerId: "alibaba", quotas: [], capturedAt: Date())
        given(succeedingProbe).probe().willReturn(snapshot)
        let alibabaWithSucceedingProbe = AlibabaProvider(probe: succeedingProbe, settingsRepository: repo)

        _ = try await alibabaWithSucceedingProbe.refresh()
        #expect(alibabaWithSucceedingProbe.lastError == nil)
        #expect(alibabaWithSucceedingProbe.snapshot != nil)
    }
}
