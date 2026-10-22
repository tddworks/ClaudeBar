import Testing
import Foundation
@testable import Quotas

/// Will it last until it resets? A forecast is a read of the quota's one
/// spend rate against its window (CANONICAL_MODEL §5).
@Suite
struct ForecastTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func quota(left: Double, length: TimeInterval?, resetsIn: TimeInterval?) -> UsageQuota {
        UsageQuota(
            percentRemaining: left,
            quotaType: .session,
            providerId: "claude",
            resetsAt: resetsIn.map { now.addingTimeInterval($0) },
            windowDuration: length
        )
    }

    private func seconds(_ duration: Duration) -> Int {
        Int((duration / .seconds(1)).rounded())
    }

    // MARK: - Runs out before it resets

    @Test
    func `should run out 34 minutes before it resets when 80 percent is spent with 1h 12m to go`() {
        // A 3h 44m window, 2h 32m gone: 20% left at this pace lasts 38m.
        let forecast = quota(left: 20, length: 13_440, resetsIn: 4_320).forecast(at: now)

        guard case .runsOut(let runsOutIn, let beforeReset) = forecast else {
            Issue.record("expected a run-out, got \(String(describing: forecast))")
            return
        }
        #expect(seconds(runsOutIn) == 2_280)
        #expect(seconds(beforeReset) == 2_040)
        #expect(forecast?.outlastsReset == false)
    }

    @Test
    func `should run out before it resets when a capped money quota is spent faster than its window`() {
        // $5 of $50 left (90% used) three quarters into the window.
        let credits = UsageQuota(
            left: .money(Money(5, currency: "USD"), of: Money(50, currency: "USD")),
            quotaType: .timeLimit("Credits"),
            providerId: "openrouter",
            resetsAt: now.addingTimeInterval(72 * 60),
            windowDuration: 5 * 3600
        )

        #expect(credits.forecast(at: now)?.outlastsReset == false)
    }

    // MARK: - Lasts until it resets

    @Test
    func `should last until it resets when spent slower than the window passes`() {
        // 10% spent over 76% of a 5h window.
        #expect(quota(left: 90, length: 5 * 3600, resetsIn: 72 * 60).forecast(at: now) == .lastsUntilReset)
    }

    @Test
    func `should last until it resets when nothing has been spent`() {
        #expect(quota(left: 100, length: 5 * 3600, resetsIn: 72 * 60).forecast(at: now) == .lastsUntilReset)
    }

    @Test
    func `should last until it resets when spent exactly as fast as the window passes`() {
        // Half used, half gone: it reaches zero as it refills, not before.
        #expect(quota(left: 50, length: 5 * 3600, resetsIn: 2.5 * 3600).forecast(at: now) == .lastsUntilReset)
    }

    // MARK: - No forecast

    @Test
    func `should have no forecast without a window or without its length`() {
        #expect(quota(left: 40, length: nil, resetsIn: nil).forecast(at: now) == nil)
        #expect(quota(left: 40, length: nil, resetsIn: 3_600).forecast(at: now) == nil)
    }

    @Test
    func `should have no forecast for a balance with no ceiling`() {
        let balance = UsageQuota(
            percentRemaining: 100,
            quotaType: .timeLimit("Credits"),
            providerId: "vercel-gateway",
            resetsAt: now.addingTimeInterval(72 * 60),
            windowDuration: 5 * 3600,
            dollarRemaining: 12.40
        )

        #expect(balance.forecast(at: now) == nil)
    }

    @Test
    func `should have no forecast when the quota is already used up`() {
        #expect(quota(left: 0, length: 5 * 3600, resetsIn: 72 * 60).forecast(at: now) == nil)
        #expect(quota(left: -10, length: 5 * 3600, resetsIn: 72 * 60).forecast(at: now) == nil)
    }

    @Test
    func `should have no forecast a minute into a weekly window`() {
        // A minute is 0.01% of a week, under the rate's 3% floor: noise, not a run-out.
        let week: TimeInterval = 7 * 86_400
        #expect(quota(left: 99, length: week, resetsIn: week - 60).forecast(at: now) == nil)
    }

    @Test
    func `should have no forecast once the window is over`() {
        #expect(quota(left: 40, length: 5 * 3600, resetsIn: -60).forecast(at: now) == nil)
    }

    // MARK: - One rate: Pace and the forecast never contradict each other

    @Test
    func `should be on track and last until it resets when 52 percent is used half way through the window`() {
        // Within the 5-point margin: Pace and the forecast both say it lasts.
        let card = quota(left: 48, length: 5 * 3600, resetsIn: 2.5 * 3600)

        #expect(card.pace(at: now) == .onPace)
        #expect(card.forecast(at: now) == .lastsUntilReset)
    }

    @Test
    func `should be on track and last until it resets when exactly 5 points ahead of the time gone`() {
        let card = quota(left: 45, length: 5 * 3600, resetsIn: 2.5 * 3600)

        #expect(card.pace(at: now) == .onPace)
        #expect(card.forecast(at: now) == .lastsUntilReset)
    }

    @Test
    func `should run hot and run out when 56 percent is used half way through the window`() {
        let card = quota(left: 44, length: 5 * 3600, resetsIn: 2.5 * 3600)

        #expect(card.pace(at: now) == .ahead)
        #expect(card.forecast(at: now)?.outlastsReset == false)
    }

    @Test
    func `should run hot and run out when 60 percent is used half way through the window`() {
        let card = quota(left: 40, length: 5 * 3600, resetsIn: 2.5 * 3600)

        #expect(card.pace(at: now) == .ahead)
        #expect(card.forecast(at: now)?.outlastsReset == false)
    }

    @Test
    func `should be on track and last until it resets when 48 percent is used half way through the window`() {
        let card = quota(left: 52, length: 5 * 3600, resetsIn: 2.5 * 3600)

        #expect(card.pace(at: now) == .onPace)
        #expect(card.forecast(at: now) == .lastsUntilReset)
    }

    @Test
    func `should have room to spare and last until it resets when 44 percent is used half way through the window`() {
        let card = quota(left: 56, length: 5 * 3600, resetsIn: 2.5 * 3600)

        #expect(card.pace(at: now) == .behind)
        #expect(card.forecast(at: now) == .lastsUntilReset)
    }

    @Test
    func `should have room to spare and last until it resets when little is used late in the window`() {
        let card = quota(left: 90, length: 5 * 3600, resetsIn: 72 * 60)

        #expect(card.pace(at: now) == .behind)
        #expect(card.forecast(at: now) == .lastsUntilReset)
    }
}
