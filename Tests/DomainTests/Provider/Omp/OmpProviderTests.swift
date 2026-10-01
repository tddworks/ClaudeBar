import Testing
import Foundation
import Mockable
@testable import Domain

@Suite("OmpProvider Tests")
@MainActor
struct OmpProviderTests {

    private func makeSettingsRepository() -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(mock).isEnabled(forProvider: .any).willReturn(true)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        return mock
    }

    // MARK: - Identity

    @Test
    func `omp provider has correct identity`() {
        let provider = OmpProvider(probe: MockUsageProbe(), settingsRepository: makeSettingsRepository())

        #expect(provider.id == "omp")
        #expect(provider.name == "Oh My Pi")
        #expect(provider.cliCommand == "omp")
        #expect(provider.dashboardURL?.host == "omp.sh")
    }

    @Test
    func `omp provider is enabled by default`() {
        let provider = OmpProvider(probe: MockUsageProbe(), settingsRepository: makeSettingsRepository())

        #expect(provider.isEnabled == true)
    }

    // MARK: - Background Polling

    @Test
    func `omp provider floors background refresh to five minutes`() {
        // `omp usage` caches upstream reports; background polls faster than
        // the cache would just respawn the CLI for identical data.
        let provider = OmpProvider(probe: MockUsageProbe(), settingsRepository: makeSettingsRepository())

        #expect(provider.backgroundRefreshFloor == .seconds(300))
    }

    // MARK: - Refresh

    @Test
    func `refresh stores snapshot and clears error on success`() async throws {
        let probe = MockUsageProbe()
        let snapshot = UsageSnapshot(
            providerId: "omp",
            quotas: [UsageQuota(percentRemaining: 42, quotaType: .timeLimit("Claude 5h"), providerId: "omp")],
            capturedAt: Date()
        )
        given(probe).probe().willReturn(snapshot)

        let provider = OmpProvider(probe: probe, settingsRepository: makeSettingsRepository())
        let result = try await provider.refresh()

        #expect(result == snapshot)
        #expect(provider.snapshot == snapshot)
        #expect(provider.lastError == nil)
        #expect(provider.isSyncing == false)
    }

    @Test
    func `refresh records error and rethrows on failure`() async {
        let probe = MockUsageProbe()
        given(probe).probe().willThrow(ProbeError.cliNotFound("omp"))

        let provider = OmpProvider(probe: probe, settingsRepository: makeSettingsRepository())

        await #expect(throws: ProbeError.cliNotFound("omp")) {
            try await provider.refresh()
        }
        #expect(provider.lastError != nil)
        #expect(provider.snapshot == nil)
    }
}
