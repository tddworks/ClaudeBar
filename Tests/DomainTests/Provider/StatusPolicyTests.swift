import Foundation
import Testing
@testable import Domain

/// One status per quota: every surface reads `status(under:)` with the
/// person's policy — absolute thresholds, or pace-aware with a burn rate.
@Suite
struct StatusPolicyTests {
    /// 40% left with 90% of a 5-hour window gone — on pace (burn rate 0.67).
    private func onPace() -> UsageQuota {
        UsageQuota(
            percentRemaining: 40, quotaType: .session, providerId: "claude",
            resetsAt: Date().addingTimeInterval(30 * 60), windowDuration: 5 * 3600
        )
    }

    /// 40% left with 20% of the window gone — burning fast (burn rate 3).
    private func burningFast() -> UsageQuota {
        UsageQuota(
            percentRemaining: 40, quotaType: .session, providerId: "claude",
            resetsAt: Date().addingTimeInterval(4 * 3600), windowDuration: 5 * 3600
        )
    }

    @Test
    func `absolute warns between 20 and 50 percent left`() {
        #expect(onPace().status(under: .absolute) == .warning)
        #expect(burningFast().status(under: .absolute) == .warning)
    }

    @Test
    func `pace-aware calls an on-pace quota healthy and a fast one a warning`() {
        let policy = StatusPolicy.paceAware(burnRateThreshold: 1.5)

        #expect(onPace().status(under: policy) == .healthy)
        #expect(burningFast().status(under: policy) == .warning)
    }

    @Test
    func `critical and depleted are absolute whatever the policy`() {
        let low = UsageQuota(
            percentRemaining: 10, quotaType: .session, providerId: "claude",
            resetsAt: Date().addingTimeInterval(60), windowDuration: 5 * 3600
        )

        #expect(low.status(under: .paceAware(burnRateThreshold: 1.5)) == .critical)
    }

    @Test
    func `a usage's overall status is its worst quota under the policy`() {
        let usage = UsageSnapshot(providerId: "claude", quotas: [onPace(), burningFast()], capturedAt: Date())
        let calm = UsageSnapshot(providerId: "claude", quotas: [onPace()], capturedAt: Date())

        #expect(usage.overallStatus(under: .paceAware(burnRateThreshold: 1.5)) == .warning)
        #expect(calm.overallStatus(under: .paceAware(burnRateThreshold: 1.5)) == .healthy)
        #expect(calm.overallStatus(under: .absolute) == .warning)
    }
}
