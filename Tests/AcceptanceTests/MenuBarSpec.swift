import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

/// Feature: Menu Bar
///
/// The menu bar icon reflects the overall quota status across
/// all enabled providers.
///
/// Behaviors covered:
/// - #1: User clicks menu bar icon → sees popup
/// - #2: Menu bar icon reflects worst quota status across providers
/// - #3: Menu bar icon appearance changes with theme
@Suite("Feature: Menu Bar")
struct MenuBarSpec {

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

    // MARK: - #2: Overall status reflects worst provider

    @Suite("Scenario: Overall status calculation")
    @MainActor
    struct OverallStatus {
        private struct TestClock: Clock {
            func sleep(for duration: Duration) async throws {}
            func sleep(nanoseconds: UInt64) async throws {}
        }

        @Test
        func `should show critical in the menu bar when one provider is critical and another healthy`() async {
            // Given — Claude healthy (70%), Codex critical (15%)
            let settings = MenuBarSpec.makeSettings()

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
                quotas: [UsageQuota(percentRemaining: 15, quotaType: .session, providerId: "codex")],
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

            // When
            await monitor.refreshAll()

            // Then — critical (worst) wins
            #expect(monitor.overallStatus == .critical)
        }

        @Test
        func `should stay healthy in the menu bar when only a turned-off provider is critical`() async {
            // Given — Claude healthy, Codex critical but disabled
            let settings = MenuBarSpec.makeSettings()

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
            codex.isPaused = true

            let monitor = QuotaMonitor(
                providers: kept([claudeProduct, codexProduct]),
                clock: TestClock()
            )

            await monitor.refreshAll()

            // Then — only enabled provider counts
            #expect(monitor.overallStatus == .healthy)
        }

        @Test
        func `should show a warning for the selected provider when it has 30% left`() async {
            // Given
            let settings = MenuBarSpec.makeSettings()

            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willReturn(UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 30, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            ))

            let claudeProduct = stubbedProduct("claude", probe: probe, settings: settings)
            let claude = claudeProduct.defaultAccount
            let monitor = QuotaMonitor(
                providers: kept([claudeProduct]),
                clock: TestClock()
            )

            // When
            await monitor.refresh(providerId: "claude")

            // Then — selected provider status reflects quota
            #expect(monitor.selectedProviderStatus == .warning)
        }

        @Test
        func `should show healthy before any quota has been read`() {
            // Given — fresh monitor, no refresh yet
            let settings = MenuBarSpec.makeSettings()
            let claudeProduct = stubbedProduct("claude", probe: MockUsageProbe(), settings: settings)
            let claude = claudeProduct.defaultAccount
            let monitor = QuotaMonitor(
                providers: kept([claudeProduct]),
                clock: TestClock()
            )

            // Then
            #expect(monitor.overallStatus == .healthy)
            #expect(monitor.selectedProviderStatus == .healthy)
        }
    }
}
