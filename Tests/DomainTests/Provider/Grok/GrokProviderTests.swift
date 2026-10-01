import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

@Suite("GrokProvider Tests")
@MainActor
struct GrokProviderTests {

    // MARK: - Identity Tests

    @Test
    func `grok provider has correct id`() {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let grok = GrokProvider(probe: mockProbe, settingsRepository: settings)

        #expect(grok.id == "grok")
    }

    @Test
    func `grok provider has correct name`() {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let grok = GrokProvider(probe: mockProbe, settingsRepository: settings)

        #expect(grok.name == "Grok")
    }

    @Test
    func `grok provider has correct cliCommand`() {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let grok = GrokProvider(probe: mockProbe, settingsRepository: settings)

        #expect(grok.cliCommand == "grok")
    }

    @Test
    func `grok provider has dashboard URL pointing to grok com`() {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let grok = GrokProvider(probe: mockProbe, settingsRepository: settings)

        #expect(grok.dashboardURL != nil)
        #expect(grok.dashboardURL?.host?.contains("grok.com") == true)
    }

    @Test
    func `grok provider has status page URL pointing to x ai`() {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let grok = GrokProvider(probe: mockProbe, settingsRepository: settings)

        #expect(grok.statusPageURL != nil)
        #expect(grok.statusPageURL?.host?.contains("x.ai") == true)
    }

    @Test
    func `grok provider is enabled by default`() {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let grok = GrokProvider(probe: mockProbe, settingsRepository: settings)

        #expect(grok.isEnabled == true)
    }

    // MARK: - State Tests

    @Test
    func `grok provider starts with no snapshot`() {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let grok = GrokProvider(probe: mockProbe, settingsRepository: settings)

        #expect(grok.snapshot == nil)
        #expect(grok.lastError == nil)
        #expect(grok.isSyncing == false)
    }

    @Test
    func `grok provider isAvailable delegates to probe`() async {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).isAvailable().willReturn(true)
        let grok = GrokProvider(probe: mockProbe, settingsRepository: settings)

        #expect(await grok.isAvailable() == true)
    }

    // MARK: - Refresh Tests

    @Test
    func `refresh updates snapshot on success`() async throws {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let expected = UsageSnapshot(
            providerId: "grok",
            quotas: [
                UsageQuota(percentRemaining: 4.0, quotaType: .weekly, providerId: "grok")
            ],
            capturedAt: Date()
        )
        given(mockProbe).probe().willReturn(expected)
        let grok = GrokProvider(probe: mockProbe, settingsRepository: settings)

        let result = try await grok.refresh()

        #expect(result == expected)
        #expect(grok.snapshot == expected)
        #expect(grok.lastError == nil)
    }

    @Test
    func `refresh records error on failure`() async {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willThrow(ProbeError.authenticationRequired)
        let grok = GrokProvider(probe: mockProbe, settingsRepository: settings)

        await #expect(throws: ProbeError.authenticationRequired) {
            try await grok.refresh()
        }
        #expect(grok.snapshot == nil)
        #expect(grok.lastError as? ProbeError == .authenticationRequired)
    }
}
