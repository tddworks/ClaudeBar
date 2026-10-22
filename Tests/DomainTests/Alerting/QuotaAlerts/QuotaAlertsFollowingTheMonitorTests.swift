import Foundation
import Mockable
import Testing
@testable import Domain

/// *Quota alerts* follow the Monitor's refreshes: each login's usage as the
/// person sees it, named as the lineup names it, with its provider.
@MainActor
@Suite
struct QuotaAlertsFollowingTheMonitorTests {
    private struct TestClock: Clock {
        func sleep(for duration: Duration) async throws {}
        func sleep(nanoseconds: UInt64) async throws {}
    }

    private final class Kept: QuotaAlertSettingsRepository, @unchecked Sendable {
        func quotaAlertPercents() -> [Int] { [35] }
        func setQuotaAlertPercents(_ percents: [Int]) {}
    }

    @Test func `should tell when a refreshed login falls below the person's percent`() async {
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(UsageSnapshot(
            providerId: "claude",
            quotas: [UsageQuota(percentRemaining: 34, quotaType: .session, providerId: "claude")],
            capturedAt: Date()
        ))
        let product = stubbedProduct("claude", probe: probe, settings: MockRepositoryFactory.makeSettingsRepository())
        let monitor = QuotaMonitor(providers: kept([product]), clock: TestClock())
        let told = RecordingDestination()
        QuotaAlerts(settings: Kept(), destination: told).follow(monitor)

        await monitor.refresh(providerId: "claude")

        #expect(told.quotaAlerts == [QuotaAlert(login: "Claude", providerId: "claude", below: 35, left: 34)])
    }
}
