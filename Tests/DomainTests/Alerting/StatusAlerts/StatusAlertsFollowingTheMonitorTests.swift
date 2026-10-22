import Foundation
import Mockable
import Testing
@testable import Domain

/// *Status alerts* follow the Monitor's refreshes: each login's status as the
/// person sees it, under their policy, named as the lineup names it.
@MainActor
@Suite
struct StatusAlertsFollowingTheMonitorTests {
    private struct TestClock: Clock {
        func sleep(for duration: Duration) async throws {}
        func sleep(nanoseconds: UInt64) async throws {}
    }

    private final class Told {
        let destination = RecordingDestination()
        var alerts: [StatusAlert] { destination.statusAlerts }
    }

    private let told = Told()

    private func claude(left: Double, resetsIn: TimeInterval? = nil) -> Provider {
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(UsageSnapshot(
            providerId: "claude",
            quotas: [UsageQuota(
                percentRemaining: left, quotaType: .session, providerId: "claude",
                resetsAt: resetsIn.map { Date().addingTimeInterval($0) },
                windowDuration: resetsIn.map { _ in 5 * 3600 }
            )],
            capturedAt: Date()
        ))
        return stubbedProduct("claude", probe: probe, settings: MockRepositoryFactory.makeSettingsRepository())
    }

    private func monitor(_ product: Provider, policy: StatusPolicy = .absolute) -> QuotaMonitor {
        let monitor = QuotaMonitor(providers: kept([product]), clock: TestClock(), statusPolicy: { policy })
        StatusAlerts(destination: told.destination).follow(monitor)
        return monitor
    }

    @Test func `should tell when a login turns critical`() async {
        let monitor = monitor(claude(left: 15))

        await monitor.refresh(providerId: "claude")

        #expect(told.alerts == [StatusAlert(login: "Claude", providerId: "claude", was: .healthy, now: .critical)])
    }

    @Test func `should stay quiet while a login stays healthy`() async {
        let monitor = monitor(claude(left: 70))

        await monitor.refresh(providerId: "claude")
        await monitor.refresh(providerId: "claude")

        #expect(told.alerts.isEmpty)
    }

    @Test func `should not warn about an on-pace quota when status is pace-aware`() async {
        // 40% left with 90% of the window gone: on pace, so healthy.
        let monitor = monitor(claude(left: 40, resetsIn: 30 * 60), policy: .paceAware(burnRateThreshold: 1.5))

        await monitor.refresh(providerId: "claude")

        #expect(told.alerts.isEmpty)
        #expect(monitor.selectedProviderStatus == .healthy)
    }

    @Test func `should warn about the same quota when status is absolute`() async {
        let monitor = monitor(claude(left: 40, resetsIn: 30 * 60), policy: .absolute)

        await monitor.refresh(providerId: "claude")

        #expect(told.alerts.map(\.now) == [.warning])
    }
}
