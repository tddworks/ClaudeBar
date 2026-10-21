import Foundation
import Testing
@testable import Domain

/// The kernel's forecast laws (CANONICAL_MODEL §5):
/// a forecast is a READ derived from the quota's own window and the usage the
/// vendor already gave; it exists only inside a window; it is the average pace
/// of the CURRENT window; and a quota that outlasts its reset reads *Lasts
/// until it resets*, never a run-out.
@Suite
struct ForecastTests {
    private func window(
        left: Double,
        hours: Double,
        resetsInMinutes: Double,
        type: QuotaType = .session
    ) -> UsageQuota {
        UsageQuota(
            percentRemaining: left,
            quotaType: type,
            providerId: "claude",
            resetsAt: Date().addingTimeInterval(resetsInMinutes * 60),
            windowDuration: hours * 3600
        )
    }

    private func seconds(_ duration: Duration?) -> Int? {
        duration.map { Int($0.components.seconds) }
    }

    // MARK: - The rate rule

    @Test
    func `should forecast a run-out from a window at a steady pace`() {
        // A 3h 44m window, 1h 12m to the reset, 80% spent: 20% left runs out in
        // 38m — 34m before it resets.
        let forecast = Forecast.of(leftPercent: 20, usedPercent: 80, elapsed: 9_120, untilReset: 4_320)

        #expect(forecast?.outlastsReset == false)
        #expect(seconds(forecast?.runsOutIn) == 2_280)
        #expect(seconds(forecast?.beforeReset) == 2_040)
        #expect(forecast?.summary == "Runs out in 38m — 34m before it resets")
    }

    @Test
    func `should report no lead over reset when the quota is already overspent`() {
        // `UsageQuota` allows a negative remaining percentage (over quota);
        // the run-out is already behind us, so it is zero — never a negative
        // time that would push `beforeReset` past `untilReset`.
        let forecast = Forecast.of(leftPercent: -10, usedPercent: 110, elapsed: 9_120, untilReset: 4_320)

        #expect(seconds(forecast?.runsOutIn) == 0)
        #expect(seconds(forecast?.beforeReset) == 4_320)
    }

    @Test
    func `should forecast a run-out from a quota whose window the vendor stated`() {
        // 5h window, 1h 12m to the reset, 90% spent: it runs out before it resets.
        let quota = window(left: 10, hours: 5, resetsInMinutes: 72)
        let forecast = quota.forecast

        #expect(forecast != nil)
        #expect(forecast?.outlastsReset == false)
        #expect(forecast?.beforeReset != nil)
        #expect(forecast?.summary.hasPrefix("Runs out in ") == true)
    }

    @Test
    func `should forecast a money quota with a ceiling from its share`() {
        // $5 of $50 left is 10%: the same share a percentage quota would have.
        let credits = UsageQuota(
            left: .money(Money(5, currency: "USD"), of: Money(50, currency: "USD")),
            quotaType: .timeLimit("Credits"),
            providerId: "openrouter",
            resetsAt: Date().addingTimeInterval(72 * 60),
            windowDuration: 5 * 3600
        )

        #expect(credits.forecast != nil)
        #expect(credits.forecast?.outlastsReset == false)
    }

    @Test
    func `should forecast a capped money quota from its share even when the percentage was left full`() {
        // A legacy construction writes 100 for a capped money quota: the
        // forecast must read the share ($5 of $50 = 10% left, 90% used), not
        // the full percentage, or 90% spent would read as "Lasts until it resets".
        let credits = UsageQuota(
            percentRemaining: 100,
            quotaType: .timeLimit("Credits"),
            providerId: "openrouter",
            resetsAt: Date().addingTimeInterval(72 * 60),
            windowDuration: 5 * 3600,
            dollarRemaining: 5,
            dollarCap: 50
        )

        #expect(credits.percentLeft == 10)
        #expect(credits.forecast?.outlastsReset == false)
        #expect(credits.forecast?.beforeReset != nil)
    }

    // MARK: - Lasts until it resets

    @Test
    func `should read Lasts until it resets when the window has been spent at nothing`() {
        let forecast = Forecast.of(leftPercent: 100, usedPercent: 0, elapsed: 13_680, untilReset: 4_320)
        let quota = window(left: 100, hours: 5, resetsInMinutes: 72)

        #expect(forecast?.outlastsReset == true)
        #expect(forecast?.beforeReset == nil)
        #expect(forecast?.summary == "Lasts until it resets")
        #expect(quota.forecast?.summary == "Lasts until it resets")
    }

    @Test
    func `should read Lasts until it resets when the quota outlasts its reset`() {
        // 10% spent over a 5h window with 1h 12m left projects far past the reset.
        let quota = window(left: 90, hours: 5, resetsInMinutes: 72)

        #expect(quota.forecast?.outlastsReset == true)
        #expect(quota.forecast?.beforeReset == nil)
        #expect(quota.forecast?.summary == "Lasts until it resets")
    }

    // MARK: - No forecast yet

    @Test
    func `should have no forecast without a window`() {
        let none = UsageQuota(percentRemaining: 40, quotaType: .session, providerId: "claude")
        let noLength = UsageQuota(
            percentRemaining: 40, quotaType: .session, providerId: "claude",
            resetsAt: Date().addingTimeInterval(3_600)
        )

        #expect(none.forecast == nil)
        #expect(noLength.forecast == nil)
    }

    @Test
    func `should have no forecast for a balance with no ceiling`() {
        let balance = UsageQuota(
            percentRemaining: 100,
            quotaType: .timeLimit("Credits"),
            providerId: "vercel-gateway",
            resetsAt: Date().addingTimeInterval(72 * 60),
            windowDuration: 5 * 3600,
            dollarRemaining: 12.40
        )

        #expect(balance.forecast == nil)
        #expect(Forecast.noForecast == "No forecast yet")
    }

    @Test
    func `should have no forecast while the window has barely been observed`() {
        // Ten seconds into a 5h window is noise, not a rate.
        let justOpened = window(left: 99, hours: 5, resetsInMinutes: 5 * 60 - 1 / 6)

        #expect(justOpened.forecast == nil)
        #expect(Forecast.of(leftPercent: 99, usedPercent: 1, elapsed: 10, untilReset: 17_990) == nil)
    }

    // MARK: - Not Pace

    @Test
    func `should forecast a run-out while Pace still reads Room to spare`() {
        // Pace judges used against elapsed; a forecast projects used forward.
        // 10% spent over 76% of the window is behind on pace, yet it still
        // lasts until the reset — the two answers never stand in for each other.
        let quota = window(left: 90, hours: 5, resetsInMinutes: 72)

        #expect(quota.pace == .behind)
        #expect(quota.forecast?.outlastsReset == true)
    }

    @Test
    func `should print a run-out in hours, minutes and days`() {
        #expect(Forecast.durationText(.seconds(38 * 60)) == "38m")
        #expect(Forecast.durationText(.seconds(3 * 3_600)) == "3h")
        #expect(Forecast.durationText(.seconds(1 * 3_600 + 12 * 60)) == "1h 12m")
        #expect(Forecast.durationText(.seconds(2 * 86_400 + 5 * 3_600)) == "2d 5h")
    }
}