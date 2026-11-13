import Foundation
import Testing
@testable import Quotas

/// One status per quota: every surface reads `status(under:)` with the
/// person's policy. Pace-aware reads the one rule `SpendRate` owns, so a quota
/// warns exactly when it runs out before it resets (CANONICAL_MODEL §5).
@Suite
struct StatusPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let length: TimeInterval = 5 * 3600

    /// A 5-hour quota with `left` percent left and `elapsed` percent of its window gone.
    private func quota(left: Double, elapsed: Double?) -> UsageQuota {
        UsageQuota(
            percentRemaining: left, quotaType: .session, providerId: "claude",
            resetsAt: elapsed.map { now.addingTimeInterval(length * (100 - $0) / 100) },
            windowDuration: elapsed == nil ? nil : length
        )
    }

    // MARK: - Absolute

    @Test
    func `should warn between 20 and 50 percent left under absolute thresholds, however fast the quota burns`() {
        #expect(quota(left: 40, elapsed: 90).status(under: .absolute, at: now) == .warning)
        #expect(quota(left: 40, elapsed: 20).status(under: .absolute, at: now) == .warning)
    }

    // MARK: - Pace-aware

    @Test
    func `should read healthy when more than half is left and it lasts until the reset`() {
        // 42% used, 41% of the window gone: On track.
        let session = quota(left: 58, elapsed: 41)

        #expect(session.pace(at: now) == .onPace)
        #expect(session.status(under: .paceAware, at: now) == .healthy)
    }

    @Test
    func `should read warning when it runs out before the reset even with most of it left`() {
        // 40% used, 15% of the window gone.
        #expect(quota(left: 60, elapsed: 15).status(under: .paceAware, at: now) == .warning)
    }

    @Test
    func `should read healthy between 20 and 50 percent left when it lasts until the reset`() {
        #expect(quota(left: 40, elapsed: 90).status(under: .paceAware, at: now) == .healthy)
        #expect(quota(left: 25, elapsed: 72).status(under: .paceAware, at: now) == .healthy)
    }

    @Test
    func `should read warning between 20 and 50 percent left when it runs out before the reset`() {
        #expect(quota(left: 40, elapsed: 20).status(under: .paceAware, at: now) == .warning)
        #expect(quota(left: 25, elapsed: 60).status(under: .paceAware, at: now) == .warning)
    }

    @Test
    func `should read healthy with little left when it lasts until the reset`() {
        // 81% used, 8 minutes of a 5-hour window to go: Room to spare.
        let session = quota(left: 19, elapsed: 97.3)

        #expect(session.pace(at: now) == .behind)
        #expect(session.status(under: .paceAware, at: now) == .healthy)
        #expect(quota(left: 15, elapsed: 95).status(under: .paceAware, at: now) == .healthy)
    }

    @Test
    func `should read warning with little left when it runs out before the reset but not soon`() {
        // 81% used at half way: empty in 35 minutes, more than a tenth of the window.
        #expect(quota(left: 19, elapsed: 50).status(under: .paceAware, at: now) == .warning)
    }

    @Test
    func `should read critical when it runs out within a tenth of the window`() {
        // 90% used, an hour to go: empty in 27 minutes.
        #expect(quota(left: 10, elapsed: 80).status(under: .paceAware, at: now) == .critical)
        // 40% used in the first 3.5% of the window: empty in 16 minutes, with most of it left.
        #expect(quota(left: 60, elapsed: 3.5).status(under: .paceAware, at: now) == .critical)
        #expect(quota(left: 5, elapsed: 50).status(under: .paceAware, at: now) == .critical)
    }

    @Test
    func `should read depleted at 0 whatever the pace`() {
        #expect(quota(left: 0, elapsed: 99).status(under: .paceAware, at: now) == .depleted)
        #expect(quota(left: 0, elapsed: 10).status(under: .paceAware, at: now) == .depleted)
    }

    @Test
    func `should fall back to the absolute bands before there is a rate`() {
        // Under the noise floor: 2% of the window gone.
        #expect(quota(left: 40, elapsed: 2).status(under: .paceAware, at: now) == .warning)
        #expect(quota(left: 70, elapsed: 2).status(under: .paceAware, at: now) == .healthy)
        // No window at all.
        #expect(quota(left: 35, elapsed: nil).status(under: .paceAware, at: now) == .warning)
        #expect(quota(left: 80, elapsed: nil).status(under: .paceAware, at: now) == .healthy)
    }

    @Test
    func `should keep a balance healthy until it is spent under pace-aware`() {
        let balance = UsageQuota(left: .money(Money(12, currency: "USD"), of: nil),
                                 quotaType: .timeLimit("Balance"), providerId: "deepseek")
        let spent = UsageQuota(left: .money(Money(0, currency: "USD"), of: nil),
                               quotaType: .timeLimit("Balance"), providerId: "deepseek")

        #expect(balance.status(under: .paceAware, at: now) == .healthy)
        #expect(spent.status(under: .paceAware, at: now) == .depleted)
    }

    @Test
    func `should never read low beside an On track or Room to spare pace`() {
        // Half-point elapsed values keep every case clear of the 5-point margin.
        for used in stride(from: 0.0, through: 98.0, by: 2.0) {
            for elapsed in stride(from: 3.5, through: 99.5, by: 4.0) {
                let session = quota(left: 100 - used, elapsed: elapsed)
                let status = session.status(under: .paceAware, at: now)
                let pace = session.pace(at: now)

                #expect(pace != .unknown)
                #expect((status >= .warning) == (pace == .ahead),
                        "used \(used)%, \(elapsed)% gone: \(status) beside \(pace)")
            }
        }
    }

    // MARK: - The policy

    @Test
    func `should follow the forecast when the person turns the warning on`() {
        #expect(StatusPolicy.from(burnRateWarningEnabled: true) == .paceAware)
        #expect(StatusPolicy.from(burnRateWarningEnabled: false) == .absolute)
    }

    @Test
    func `should show the provider's status as its worst quota under the person's policy`() {
        let lasting = quota(left: 40, elapsed: 90)
        let runningOut = quota(left: 60, elapsed: 15)
        let usage = UsageSnapshot(providerId: "claude", quotas: [lasting, runningOut], capturedAt: now)
        let calm = UsageSnapshot(providerId: "claude", quotas: [lasting], capturedAt: now)

        #expect(usage.overallStatus(under: .paceAware, at: now) == .warning)
        #expect(calm.overallStatus(under: .paceAware, at: now) == .healthy)
        #expect(calm.overallStatus(under: .absolute, at: now) == .warning)
    }

    // MARK: - Roll-ups read the policy

    @Test
    func `should read a collapsed group by its worst quota under the person's policy`() {
        let group = QuotaGroup(title: "Claude", quotas: [quota(left: 19, elapsed: 97.3), quota(left: 90, elapsed: 10)])

        #expect(group.worstStatus(under: .paceAware, at: now) == .healthy)
        #expect(group.worstStatus(under: .absolute, at: now) == .critical)
    }

    @Test
    func `should name the quota that sets the status under the person's policy, not the one with the least left`() {
        let lasting = quota(left: 19, elapsed: 97.3)    // healthy under pace-aware
        let runningOut = quota(left: 60, elapsed: 3.5)  // empty in about 16 minutes: critical
        let snapshot = UsageSnapshot(providerId: "claude", quotas: [lasting, runningOut], capturedAt: now)

        #expect(snapshot.worstQuota(under: .paceAware, at: now) == runningOut)
        #expect(snapshot.worstQuota(under: .absolute, at: now) == lasting)
    }

    @Test
    func `should lead with the quota that sets the status, then the one with the least left`() {
        let lasting = quota(left: 19, elapsed: 97.3)    // healthy under pace-aware
        let runningOut = quota(left: 60, elapsed: 3.5)  // empty in about 16 minutes: critical
        let roomy = quota(left: 80, elapsed: 50)        // healthy
        let snapshot = UsageSnapshot(providerId: "claude", quotas: [roomy, lasting, runningOut], capturedAt: now)

        #expect(snapshot.quotasWorstFirst(under: .paceAware, at: now) == [runningOut, lasting, roomy])
        #expect(snapshot.quotasWorstFirst(under: .absolute, at: now) == [lasting, runningOut, roomy])
    }
}
