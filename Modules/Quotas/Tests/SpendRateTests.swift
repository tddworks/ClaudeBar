import Testing
import Foundation
@testable import Quotas

/// How fast a quota is spent against its window — the one rate Pace, the
/// pace tick, the status and the forecast all read.
@Suite
struct SpendRateTests {

    @Test
    func `should be the share used over the share of the window gone`() {
        #expect(SpendRate(percentUsed: 30, percentTimeElapsed: 60)?.value == 0.5)
        #expect(SpendRate(percentUsed: 70, percentTimeElapsed: 25)?.value == 2.8)
    }

    @Test
    func `should have no rate before 3 percent of the window or once it is over`() {
        #expect(SpendRate(percentUsed: 1, percentTimeElapsed: 2.9) == nil)
        #expect(SpendRate(percentUsed: 1, percentTimeElapsed: 100) == nil)
        #expect(SpendRate(percentUsed: 1, percentTimeElapsed: 3) != nil)
    }

    @Test
    func `should run out before the reset only when more than 5 points ahead of the time gone`() {
        #expect(SpendRate(percentUsed: 56, percentTimeElapsed: 50)?.runsOutBeforeReset == true)
        #expect(SpendRate(percentUsed: 55.1, percentTimeElapsed: 50)?.runsOutBeforeReset == true)
        #expect(SpendRate(percentUsed: 55, percentTimeElapsed: 50)?.runsOutBeforeReset == false)
        #expect(SpendRate(percentUsed: 52, percentTimeElapsed: 50)?.runsOutBeforeReset == false)
        #expect(SpendRate(percentUsed: 0, percentTimeElapsed: 50)?.runsOutBeforeReset == false)
    }

    @Test
    func `should have room to spare only when more than 5 points behind the time gone`() {
        #expect(SpendRate(percentUsed: 44, percentTimeElapsed: 50)?.hasRoomToSpare == true)
        #expect(SpendRate(percentUsed: 44.9, percentTimeElapsed: 50)?.hasRoomToSpare == true)
        #expect(SpendRate(percentUsed: 45, percentTimeElapsed: 50)?.hasRoomToSpare == false)
        #expect(SpendRate(percentUsed: 56, percentTimeElapsed: 50)?.hasRoomToSpare == false)
    }

    @Test
    func `should read the quota's share left, not a full percentage written for a capped money quota`() {
        // $5 of $50 left is 90% used, whatever percentage the old shape wrote.
        let now = Date()
        let credits = UsageQuota(
            percentRemaining: 100,
            quotaType: .timeLimit("Credits"),
            providerId: "openrouter",
            resetsAt: now.addingTimeInterval(2.5 * 3600),
            windowDuration: 5 * 3600,
            dollarRemaining: 5,
            dollarCap: 50
        )

        #expect(credits.rate(at: now)?.percentUsed == 90)
    }

    @Test
    func `should have no rate for a balance with no ceiling`() {
        let now = Date()
        let balance = UsageQuota(
            percentRemaining: 100,
            quotaType: .timeLimit("Credits"),
            providerId: "vercel-gateway",
            resetsAt: now.addingTimeInterval(2.5 * 3600),
            windowDuration: 5 * 3600,
            dollarRemaining: 12.40
        )

        #expect(balance.rate(at: now) == nil)
    }
}
