import Foundation
import Testing
import Mockable
@testable import Domain
@testable import Infrastructure

/// A login paused from the popover is off the *All* page, which is the
/// popover's own (`Overview`); the rest of what a pause does is the Monitor's,
/// in `MonitoringTests`' `PausedLoginsTests`
/// (docs/features/providers/multi-account/design.md §3.5).
@MainActor
@Suite
struct PausedLoginsAllPageTests {
    private func quota(_ left: Double) -> UsageQuota {
        UsageQuota(percentRemaining: left, quotaType: .session, providerId: "p")
    }

    private func snapshot(_ quotas: UsageQuota...) -> UsageSnapshot {
        UsageSnapshot(providerId: "p", quotas: quotas, capturedAt: Date())
    }

    @Test
    func `should leave a paused login out of the All page`() async throws {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(snapshot(quota(9)))
        let claude = stubbedProduct("claude", probe: probe, settings: settings)
        let gemini = stubbedProduct("gemini", probe: probe, settings: settings)
        let monitor = QuotaMonitor(providers: kept([claude, gemini]))
        await monitor.refresh(providerId: "claude")
        #expect(Overview(monitor).cards.map(\.id) == ["claude", "gemini"])

        monitor.pause(claude.defaultAccount)

        #expect(Overview(monitor).cards.map(\.id) == ["gemini"])
    }
}
