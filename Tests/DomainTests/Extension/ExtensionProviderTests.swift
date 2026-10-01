import Foundation
import Testing
import Mockable
@testable import Domain

@Suite
@MainActor
struct ExtensionProviderTests {
    // MARK: - Identity

    @Test
    func `provider has correct identity from manifest`() {
        let manifest = makeManifest(id: "openrouter", name: "OpenRouter")
        let provider = ExtensionProvider(
            manifest: manifest,
            probes: [:],
            settingsRepository: makeSettingsRepository()
        )

        #expect(provider.id == "ext-openrouter")
        #expect(provider.name == "OpenRouter")
        #expect(provider.cliCommand == "")
        #expect(provider.dashboardURL == URL(string: "https://openrouter.ai/activity"))
    }

    @Test
    func `provider id is prefixed with ext to avoid collisions`() {
        let manifest = makeManifest(id: "claude", name: "Claude Clone")
        let provider = ExtensionProvider(
            manifest: manifest,
            probes: [:],
            settingsRepository: makeSettingsRepository()
        )

        #expect(provider.id == "ext-claude")
    }

    // MARK: - Enabled State

    @Test
    func `provider reads enabled state from settings`() {
        let settings = MockProviderSettingsRepository()
        given(settings).isEnabled(forProvider: .any, defaultValue: .any).willReturn(false)
        given(settings).isEnabled(forProvider: .any).willReturn(false)
        given(settings).setEnabled(.any, forProvider: .any).willReturn()
        given(settings).customCardURL(forProvider: .any).willReturn(nil)
        given(settings).setCustomCardURL(.any, forProvider: .any).willReturn()

        let provider = ExtensionProvider(
            manifest: makeManifest(id: "test", name: "Test"),
            probes: [:],
            settingsRepository: settings
        )

        #expect(provider.isEnabled == false)
    }

    @Test
    func `provider writes enabled state to settings`() {
        let settings = makeSettingsRepository()
        given(settings).setEnabled(.any, forProvider: .any).willReturn()

        let provider = ExtensionProvider(
            manifest: makeManifest(id: "test", name: "Test"),
            probes: [:],
            settingsRepository: settings
        )

        provider.isEnabled = false

        verify(settings).setEnabled(.value(false), forProvider: .value("ext-test")).called(1)
    }

    // MARK: - Refresh

    @Test
    func `refresh runs all section probes and merges snapshots`() async throws {
        let quotaProbe = MockUsageProbe()
        let quotaSnapshot = UsageSnapshot(
            providerId: "ext-test",
            quotas: [UsageQuota(percentRemaining: 80, quotaType: .weekly, providerId: "ext-test")],
            capturedAt: Date()
        )
        given(quotaProbe).probe().willReturn(quotaSnapshot)

        let metricsProbe = MockUsageProbe()
        let metricsSnapshot = UsageSnapshot(
            providerId: "ext-test",
            quotas: [],
            capturedAt: Date(),
            extensionMetrics: [ExtensionMetric(label: "Cost", value: "$5", unit: "USD")]
        )
        given(metricsProbe).probe().willReturn(metricsSnapshot)

        let provider = ExtensionProvider(
            manifest: makeManifest(id: "test", name: "Test"),
            probes: ["quotas": quotaProbe, "metrics": metricsProbe],
            settingsRepository: makeSettingsRepository()
        )

        let result = try await provider.refresh()

        #expect(result.quotas.count == 1)
        #expect(result.quotas[0].percentRemaining == 80)
        #expect(result.extensionMetrics?.count == 1)
        #expect(result.extensionMetrics?[0].label == "Cost")
        #expect(provider.snapshot != nil)
    }

    @Test
    func `refresh sets isSyncing during probe execution`() async throws {
        let probe = MockUsageProbe()
        given(probe).probe().willReturn(
            UsageSnapshot(providerId: "ext-test", quotas: [], capturedAt: Date())
        )

        let provider = ExtensionProvider(
            manifest: makeManifest(id: "test", name: "Test"),
            probes: ["q": probe],
            settingsRepository: makeSettingsRepository()
        )

        #expect(provider.isSyncing == false)

        _ = try await provider.refresh()

        // After refresh completes, isSyncing should be false
        #expect(provider.isSyncing == false)
        #expect(provider.snapshot != nil)
    }

    @Test
    func `refresh stores error on probe failure`() async {
        let probe = MockUsageProbe()
        given(probe).probe().willThrow(ProbeError.executionFailed("script failed"))

        let provider = ExtensionProvider(
            manifest: makeManifest(id: "test", name: "Test"),
            probes: ["q": probe],
            settingsRepository: makeSettingsRepository()
        )

        do {
            _ = try await provider.refresh()
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(provider.lastError != nil)
            #expect(provider.isSyncing == false)
        }
    }

    @Test
    func `refresh continues when one probe fails but others succeed`() async throws {
        let goodProbe = MockUsageProbe()
        given(goodProbe).probe().willReturn(
            UsageSnapshot(
                providerId: "ext-test",
                quotas: [UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "ext-test")],
                capturedAt: Date()
            )
        )

        let badProbe = MockUsageProbe()
        given(badProbe).probe().willThrow(ProbeError.timeout)

        let provider = ExtensionProvider(
            manifest: makeManifest(id: "test", name: "Test"),
            probes: ["good": goodProbe, "bad": badProbe],
            settingsRepository: makeSettingsRepository()
        )

        let result = try await provider.refresh()

        // Should still have data from the successful probe
        #expect(result.quotas.count == 1)
    }

    // MARK: - Availability

    @Test
    func `isAvailable returns true when at least one probe is available`() async {
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)

        let provider = ExtensionProvider(
            manifest: makeManifest(id: "test", name: "Test"),
            probes: ["q": probe],
            settingsRepository: makeSettingsRepository()
        )

        let available = await provider.isAvailable()
        #expect(available == true)
    }

    @Test
    func `isAvailable returns false when no probes are available`() async {
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(false)

        let provider = ExtensionProvider(
            manifest: makeManifest(id: "test", name: "Test"),
            probes: ["q": probe],
            settingsRepository: makeSettingsRepository()
        )

        let available = await provider.isAvailable()
        #expect(available == false)
    }

    // MARK: - Helpers

    private func makeManifest(id: String, name: String) -> ExtensionManifest {
        ExtensionManifest(
            id: id,
            name: name,
            version: "1.0.0",
            dashboardURL: URL(string: "https://openrouter.ai/activity"),
            sections: [
                ExtensionSection(id: "q", type: .quotaGrid, probeCommand: "./probe.sh")
            ]
        )
    }

    private func makeSettingsRepository() -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(mock).isEnabled(forProvider: .any).willReturn(true)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        given(mock).customCardURL(forProvider: .any).willReturn(nil)
        given(mock).setCustomCardURL(.any, forProvider: .any).willReturn()
        return mock
    }
}
