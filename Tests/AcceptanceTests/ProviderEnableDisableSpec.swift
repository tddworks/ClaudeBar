import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

/// Feature: Provider Enable/Disable
///
/// Users toggle providers on/off from Settings. Disabled providers
/// are hidden from pills and excluded from monitoring.
///
/// Behaviors covered:
/// - #46: User toggles provider off → removed from pills, excluded from monitoring
/// - #47: User toggles provider on → appears in pills, included in monitoring
/// - #48: Enabled state persists across restarts
@Suite("Feature: Provider Enable/Disable")
struct ProviderEnableDisableSpec {

    private struct TestClock: Clock {
        func sleep(for duration: Duration) async throws {}
        func sleep(nanoseconds: UInt64) async throws {}
    }

    private static func makeSettings() -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(mock).isEnabled(forProvider: .any).willReturn(true)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        return mock
    }

    // MARK: - #46: Disable provider excludes from monitoring

    @Suite("Scenario: Disable a provider")
    @MainActor
    struct DisableProvider {
        private struct TestClock: Clock {
            func sleep(for duration: Duration) async throws {}
            func sleep(nanoseconds: UInt64) async throws {}
        }

        @Test
        func `should not read a turned-off provider's quotas when every provider refreshes`() async {
            // Given — Claude enabled, Codex disabled
            let settings = ProviderEnableDisableSpec.makeSettings()

            let claudeProbe = MockUsageProbe()
            given(claudeProbe).isAvailable().willReturn(true)
            given(claudeProbe).probe().willReturn(UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 70, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            ))

            let codexProbe = MockUsageProbe()
            // No setup — Codex should never be called

            let claudeProduct = stubbedProduct("claude", probe: claudeProbe, settings: settings)
            let claude = claudeProduct.defaultAccount
            let codexProduct = stubbedProduct("codex", probe: codexProbe, settings: settings)
            let codex = codexProduct.defaultAccount
            codex.isEnabled = false

            let monitor = QuotaMonitor(
                providers: kept([claudeProduct, codexProduct]),
                clock: TestClock()
            )

            // When
            await monitor.refreshAll()

            // Then — Claude refreshed, Codex skipped
            #expect(claude.snapshot != nil)
            #expect(codex.snapshot == nil)
        }

        @Test
        func `should turn the menu bar healthy when the person turns off the only critical provider`() async {
            // Given — Claude healthy, Codex critical but disabled
            let settings = ProviderEnableDisableSpec.makeSettings()

            let claudeProbe = MockUsageProbe()
            given(claudeProbe).isAvailable().willReturn(true)
            given(claudeProbe).probe().willReturn(UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 70, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            ))

            let codexProbe = MockUsageProbe()
            given(codexProbe).isAvailable().willReturn(true)
            given(codexProbe).probe().willReturn(UsageSnapshot(
                providerId: "codex",
                quotas: [UsageQuota(percentRemaining: 5, quotaType: .session, providerId: "codex")],
                capturedAt: Date()
            ))

            let claudeProduct = stubbedProduct("claude", probe: claudeProbe, settings: settings)
            let claude = claudeProduct.defaultAccount
            let codexProduct = stubbedProduct("codex", probe: codexProbe, settings: settings)
            let codex = codexProduct.defaultAccount
            let monitor = QuotaMonitor(
                providers: kept([claudeProduct, codexProduct]),
                clock: TestClock()
            )

            await monitor.refreshAll()
            #expect(monitor.overallStatus == .critical)

            // When — user disables Codex
            codex.isEnabled = false

            // Then — overall status improves to healthy
            #expect(monitor.overallStatus == .healthy)
        }
    }

    // MARK: - #47: Enable provider without changing selection

    @Suite("Scenario: Enable a provider")
    @MainActor
    struct EnableProvider {
        private struct TestClock: Clock {
            func sleep(for duration: Duration) async throws {}
            func sleep(nanoseconds: UInt64) async throws {}
        }

        @Test
        func `should add Codex to the lineup and keep Claude selected when the person resumes Codex`() {
            // Given — Claude selected, Codex paused
            let settings = ProviderEnableDisableSpec.makeSettings()
            let claudeProduct = stubbedProduct("claude", probe: MockUsageProbe(), settings: settings)
            let codexProduct = stubbedProduct("codex", probe: MockUsageProbe(), settings: settings)
            let codex = codexProduct.defaultAccount
            codex.isEnabled = false

            let monitor = QuotaMonitor(
                providers: kept([claudeProduct, codexProduct]),
                clock: TestClock()
            )
            #expect(monitor.selectedProviderId == "claude")

            // When — the person resumes Codex
            monitor.resume(codex)

            // Then — Codex is watched again, Claude still selected
            #expect(codex.isEnabled == true)
            #expect(monitor.lineup.count == 2)
            #expect(monitor.selectedProviderId == "claude")
        }
    }

    // MARK: - #48: Enabled state persists

    @Suite("Scenario: Enabled state persists across restarts")
    @MainActor
    struct PersistEnabledState {

        @Test
        func `should remember whether the person turned a provider on or off`() {
            // Given — settings of its own
            let repo = isolatedSettings()

            // When — set enabled to false
            repo.setEnabled(false, forProvider: "codex")

            // Then — persisted value is false
            #expect(repo.isEnabled(forProvider: "codex", defaultValue: true) == false)

            // When — set enabled to true
            repo.setEnabled(true, forProvider: "codex")

            // Then — persisted value is true
            #expect(repo.isEnabled(forProvider: "codex", defaultValue: true) == true)
        }
    }
}
