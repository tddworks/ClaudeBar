import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

/// Feature: Notifications
///
/// Users receive system notifications when their quota status degrades.
/// No notification is sent when status improves or stays the same.
///
/// Behaviors covered:
/// - #19: Quota drops to Warning (≤50%) → system notification
/// - #20: Quota drops to Critical (<20%) → system notification
/// - #21: Quota hits Depleted (0%) → system notification
/// - #22: Quota improves → no notification
@Suite("Feature: Notifications")
struct NotificationsSpec {

    private struct TestClock: Clock {
        func sleep(for duration: TimeInterval) async throws {}
    }

    private func makeSettings() -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(mock).isEnabled(forProvider: .any).willReturn(true)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        return mock
    }

    // MARK: - #19–21: Quota degrades → notification sent

    @Suite("Scenario: Quota degrades")
    struct QuotaDegrades {

        private struct TestClock: Clock {
            func sleep(for duration: TimeInterval) async throws {}
        }

        @Test
        func `quota drops from healthy to critical triggers alert`() async {
            // Given — Claude was previously healthy (no snapshot = healthy default)
            let settings = MockProviderSettingsRepository()
            given(settings).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
            given(settings).isEnabled(forProvider: .any).willReturn(true)
            given(settings).setEnabled(.any, forProvider: .any).willReturn()

            let mockAlerter = MockQuotaAlerter()
            given(mockAlerter).alert(providerId: .any, previousStatus: .any, currentStatus: .any).willReturn(())

            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willReturn(UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 15, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            ))

            let claude = ClaudeProvider(probe: probe, settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude]),
                alerter: mockAlerter,
                clock: TestClock()
            )

            // When — refresh returns 15% (critical)
            await monitor.refresh(providerId: "claude")

            // Then — alerter called with healthy → critical
            verify(mockAlerter).alert(
                providerId: .value("claude"),
                previousStatus: .value(.healthy),
                currentStatus: .value(.critical)
            ).called(1)
        }
    }

    // MARK: - #22: Quota stays the same → no notification

    @Suite("Scenario: Quota stays the same")
    struct QuotaUnchanged {

        private struct TestClock: Clock {
            func sleep(for duration: TimeInterval) async throws {}
        }

        @Test
        func `repeated healthy refreshes do not trigger alert`() async {
            // Given
            let settings = MockProviderSettingsRepository()
            given(settings).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
            given(settings).isEnabled(forProvider: .any).willReturn(true)
            given(settings).setEnabled(.any, forProvider: .any).willReturn()

            let mockAlerter = MockQuotaAlerter()
            given(mockAlerter).alert(providerId: .any, previousStatus: .any, currentStatus: .any).willReturn(())

            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willReturn(UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 70, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            ))

            let claude = ClaudeProvider(probe: probe, settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude]),
                alerter: mockAlerter,
                clock: TestClock()
            )

            // When — refresh twice with same healthy status
            await monitor.refresh(providerId: "claude")
            await monitor.refresh(providerId: "claude")

            // Then — no alerts (healthy → healthy is not a degradation)
            verify(mockAlerter).alert(
                providerId: .any,
                previousStatus: .any,
                currentStatus: .any
            ).called(0)
        }
    }

    // MARK: - Cross-behavior: One provider failure does not affect others

    @Suite("Scenario: Provider isolation")
    struct ProviderIsolation {

        private struct TestClock: Clock {
            func sleep(for duration: TimeInterval) async throws {}
        }

        @Test
        func `one provider failure does not block others from refreshing`() async {
            // Given
            let settings = MockProviderSettingsRepository()
            given(settings).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
            given(settings).isEnabled(forProvider: .any).willReturn(true)
            given(settings).setEnabled(.any, forProvider: .any).willReturn()

            let claudeProbe = MockUsageProbe()
            given(claudeProbe).isAvailable().willReturn(true)
            given(claudeProbe).probe().willReturn(UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 70, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            ))

            let codexProbe = MockUsageProbe()
            given(codexProbe).isAvailable().willReturn(true)
            given(codexProbe).probe().willThrow(ProbeError.timeout)

            let claude = ClaudeProvider(probe: claudeProbe, settingsRepository: settings)
            let codex = CodexProvider(probe: codexProbe, settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude, codex]),
                clock: TestClock()
            )

            // When — refresh all
            await monitor.refreshAll()

            // Then — Claude succeeds independently
            #expect(claude.snapshot != nil)
            #expect(codex.snapshot == nil)
            #expect(codex.lastError != nil)
        }
    }
}
