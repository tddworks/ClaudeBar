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

    /// What the person was told, so a scenario asserts it.
    final class Told: AlertDestination, @unchecked Sendable {
        var alerts: [StatusAlert] = []
        func announce(_ alert: Alert) async { if case .status(let status) = alert { alerts.append(status) } }
    }

    private struct TestClock: Clock {
        func sleep(for duration: Duration) async throws {}
        func sleep(nanoseconds: UInt64) async throws {}
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
    @MainActor
    struct QuotaDegrades {

        private struct TestClock: Clock {
            func sleep(for duration: Duration) async throws {}
            func sleep(nanoseconds: UInt64) async throws {}
        }

        @Test
        func `should alert the person that Claude went from healthy to critical when its quota drops to 15%`() async {
            // Given — Claude was previously healthy (no snapshot = healthy default)
            let settings = MockProviderSettingsRepository()
            given(settings).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
            given(settings).isEnabled(forProvider: .any).willReturn(true)
            given(settings).setEnabled(.any, forProvider: .any).willReturn()

            let told = Told()

            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willReturn(UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 15, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            ))

            let claudeProduct = stubbedProduct("claude", probe: probe, settings: settings)
            let monitor = QuotaMonitor(
                providers: kept([claudeProduct]),
                clock: TestClock()
            )
            StatusAlerts(destination: told).follow(monitor)

            // When — refresh returns 15% (critical)
            await monitor.refresh(providerId: "claude")

            // Then — told once: healthy → critical
            #expect(told.alerts == [StatusAlert(login: "Claude", providerId: "claude", was: .healthy, now: .critical)])
        }
    }

    // MARK: - #22: Quota stays the same → no notification

    @Suite("Scenario: Quota stays the same")
    @MainActor
    struct QuotaUnchanged {

        private struct TestClock: Clock {
            func sleep(for duration: Duration) async throws {}
            func sleep(nanoseconds: UInt64) async throws {}
        }

        @Test
        func `should not alert the person when the quota stays healthy`() async {
            // Given
            let settings = MockProviderSettingsRepository()
            given(settings).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
            given(settings).isEnabled(forProvider: .any).willReturn(true)
            given(settings).setEnabled(.any, forProvider: .any).willReturn()

            let told = Told()

            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willReturn(UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 70, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            ))

            let claudeProduct = stubbedProduct("claude", probe: probe, settings: settings)
            let monitor = QuotaMonitor(
                providers: kept([claudeProduct]),
                clock: TestClock()
            )
            StatusAlerts(destination: told).follow(monitor)

            // When — refresh twice with same healthy status
            await monitor.refresh(providerId: "claude")
            await monitor.refresh(providerId: "claude")

            // Then — no alerts (healthy → healthy is not a degradation)
            #expect(told.alerts.isEmpty)
        }
    }

    // MARK: - Cross-behavior: One provider failure does not affect others

    @Suite("Scenario: Provider isolation")
    @MainActor
    struct ProviderIsolation {

        private struct TestClock: Clock {
            func sleep(for duration: Duration) async throws {}
            func sleep(nanoseconds: UInt64) async throws {}
        }

        @Test
        func `should still show Claude's quotas when Codex times out`() async {
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
            given(codexProbe).probe().willThrow(UsageError.timeout)

            let claudeProduct = stubbedProduct("claude", probe: claudeProbe, settings: settings)
            let claude = claudeProduct.defaultAccount
            let codexProduct = stubbedProduct("codex", probe: codexProbe, settings: settings)
            let codex = codexProduct.defaultAccount
            let monitor = QuotaMonitor(
                providers: kept([claudeProduct, codexProduct]),
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
