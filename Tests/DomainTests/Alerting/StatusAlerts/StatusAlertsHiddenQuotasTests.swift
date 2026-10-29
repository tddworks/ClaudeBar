import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

/// Issue #140: a hidden quota never sets an alert. What hiding does to the
/// Monitor's aggregates is in `MonitoringTests`' `QuotaMonitorHiddenQuotasTests`.
@Suite
@MainActor
struct StatusAlertsHiddenQuotasTests {
    private struct TestClock: Clock {
        func sleep(for duration: Duration) async throws {}
        func sleep(nanoseconds: UInt64) async throws {}
    }

    /// Records the status alerts it was told, so a test asserts state.
    private final class Told {
        let destination = RecordingDestination()
        var alerts: [StatusAlert] { destination.statusAlerts }
    }

    /// Gemini-style snapshot: session and weekly healthy, flash critical (10%).
    private func makeGeminiProbe() -> MockUsageProbe {
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(UsageSnapshot(
            providerId: "gemini",
            quotas: [
                UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "gemini"),
                UsageQuota(percentRemaining: 70, quotaType: .weekly, providerId: "gemini"),
                UsageQuota(percentRemaining: 10, quotaType: .modelSpecific("gemini-2.0-flash"), providerId: "gemini"),
            ],
            capturedAt: Date()
        ))
        return probe
    }

    private func makeSettings(hiddenKeys: Set<String>) -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(mock).isEnabled(forProvider: .any).willReturn(true)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        given(mock).hiddenQuotaKeys(forProvider: .any).willReturn(hiddenKeys)
        given(mock).providerOrder().willReturn([])
        given(mock).setProviderOrder(.any).willReturn()
        return mock
    }

    private func makeRefreshedGeminiMonitor(hiddenKeys: Set<String>, told: Told) async {
        let settings = makeSettings(hiddenKeys: hiddenKeys)
        let providerProduct = stubbedProduct("gemini", probe: makeGeminiProbe(), settings: settings)
        let monitor = QuotaMonitor(
            providers: kept([providerProduct]),
            clock: TestClock(),
            settingsRepository: settings
        )
        StatusAlerts(destination: told.destination).follow(monitor)
        await monitor.refresh(providerId: "gemini")
    }

    @Test
    func `should not alert the person when only a hidden quota turns critical`() async {
        // Given — the critical flash model is hidden
        let told = Told()
        await makeRefreshedGeminiMonitor(hiddenKeys: ["model:gemini-2.0-flash"], told: told)

        // Then — the visible status is healthy, so there is nothing to alert about
        #expect(told.alerts.isEmpty)
    }

    @Test
    func `should alert the person when a quota they can see turns critical`() async {
        // Given — nothing hidden, so the snapshot is critical
        let told = Told()
        await makeRefreshedGeminiMonitor(hiddenKeys: [], told: told)

        // Then — healthy → critical on first refresh
        #expect(told.alerts == [StatusAlert(login: "Gemini", providerId: "gemini", was: .healthy, now: .critical)])
    }
}
