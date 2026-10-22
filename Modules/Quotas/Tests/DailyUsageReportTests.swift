import Foundation
import Testing
@testable import Quotas

@Suite
struct DailyUsageReportTests {
    private func makeReport(
        todayCost: Decimal = 14.26,
        todayTokens: Int = 19_498_439,
        todayTime: TimeInterval = 80160, // 22h 16m
        prevCost: Decimal = 41.73,
        prevTokens: Int = 59_706_443,
        prevTime: TimeInterval = 70620 // 19h 37m
    ) -> DailyUsageReport {
        DailyUsageReport(
            today: DailyUsageStat(
                date: Date(),
                totalCost: todayCost,
                totalTokens: todayTokens,
                workingTime: todayTime,
                sessionCount: 3
            ),
            previous: DailyUsageStat(
                date: Date().addingTimeInterval(-86400),
                totalCost: prevCost,
                totalTokens: prevTokens,
                workingTime: prevTime,
                sessionCount: 5
            )
        )
    }

    // MARK: - Cost Delta

    @Test func `should show a negative cost change when today costs less than the day before`() {
        let report = makeReport(todayCost: 14.26, prevCost: 41.73)
        #expect(report.costDelta == Decimal(string: "-27.47")!)
    }

    @Test func `should show a positive cost change when today costs more than the day before`() {
        let report = makeReport(todayCost: 50, prevCost: 20)
        #expect(report.costDelta == 30)
    }

    @Test func `should show the cost change as a percent of the day before`() {
        let report = makeReport(todayCost: 14.26, prevCost: 41.73)
        let percent = report.costChangePercent!
        // 14.26 / 41.73 - 1 ≈ -65.8%
        #expect(percent < -65 && percent > -66)
    }

    @Test func `should show no cost change percent when the day before cost nothing`() {
        let report = makeReport(todayCost: 10, prevCost: 0)
        #expect(report.costChangePercent == nil)
    }

    @Test func `should print a cost drop with a minus sign and dollars`() {
        let report = makeReport(todayCost: 14.26, prevCost: 41.73)
        #expect(report.formattedCostDelta == "-$27.47")
    }

    @Test func `should print a cost rise with a plus sign`() {
        let report = makeReport(todayCost: 50, prevCost: 20)
        #expect(report.formattedCostDelta == "+$30.00")
    }

    // MARK: - Token Delta

    @Test func `should show a negative token change when today used fewer tokens`() {
        let report = makeReport(todayTokens: 19_498_439, prevTokens: 59_706_443)
        #expect(report.tokenDelta == -40_208_004)
    }

    @Test func `should print a token change in millions`() {
        let report = makeReport(todayTokens: 19_498_439, prevTokens: 59_706_443)
        #expect(report.formattedTokenDelta == "-40.2M")
    }

    @Test func `should print a token rise with a plus sign`() {
        let report = makeReport(todayTokens: 50_000_000, prevTokens: 10_000_000)
        #expect(report.formattedTokenDelta == "+40.0M")
    }

    @Test func `should show the token change as a percent of the day before`() {
        let report = makeReport(todayTokens: 19_498_439, prevTokens: 59_706_443)
        let percent = report.tokenChangePercent!
        // (19.5M - 59.7M) / 59.7M ≈ -67.3%
        #expect(percent < -67 && percent > -68)
    }

    // MARK: - Time Delta

    @Test func `should show a positive time change when today has more working time`() {
        let report = makeReport(todayTime: 80160, prevTime: 70620)
        #expect(report.timeDelta == 9540) // +2h 39m
    }

    @Test func `should print a time change in hours and minutes`() {
        let report = makeReport(todayTime: 80160, prevTime: 70620)
        #expect(report.formattedTimeDelta == "+2h 39m")
    }

    @Test func `should print a time drop with a minus sign`() {
        let report = makeReport(todayTime: 3600, prevTime: 7200)
        #expect(report.formattedTimeDelta == "-1h 0m")
    }

    @Test func `should show the working time change as a percent of the day before`() {
        let report = makeReport(todayTime: 80160, prevTime: 70620)
        let percent = report.timeChangePercent!
        // 9540 / 70620 ≈ 13.5%
        #expect(percent > 13 && percent < 14)
    }

    // MARK: - Progress

    @Test func `should fill the cost bar with today's share of both days' cost`() {
        let report = makeReport(todayCost: 25, prevCost: 75)
        #expect(report.costProgress == 0.25)
    }

    @Test func `should fill the token bar with today's share of both days' tokens`() {
        let report = makeReport(todayTokens: 1000, prevTokens: 3000)
        #expect(report.tokenProgress == 0.25)
    }

    @Test func `should leave every bar empty when both days have no usage`() {
        let report = makeReport(todayCost: 0, todayTokens: 0, todayTime: 0, prevCost: 0, prevTokens: 0, prevTime: 0)
        #expect(report.costProgress == 0)
        #expect(report.tokenProgress == 0)
        #expect(report.timeProgress == 0)
    }

    // MARK: - Cache Deltas

    private func makeCacheReport(
        todayHitRate: Double,
        prevHitRate: Double,
        todaySavings: Decimal = 100,
        prevSavings: Decimal = 50,
        todayCacheTokens: Int = 0,
        prevCacheTokens: Int = 0
    ) -> DailyUsageReport {
        // Synthesize input/cache_read counts to produce target hit rates
        // hit = cr / (cr + input) → set input = 1000, cr = 1000 * hit / (1 - hit)
        func make(input: Int, cacheRead: Int, savings: Decimal, cacheTokens: Int, date: Date) -> DailyUsageStat {
            DailyUsageStat(
                date: date,
                totalCost: 0,
                totalTokens: input,
                workingTime: 0,
                sessionCount: 1,
                inputTokens: input,
                outputTokens: 0,
                cacheCreationTokens: cacheTokens,
                cacheReadTokens: cacheRead,
                cachedSavings: savings
            )
        }
        let todayInput = 1000
        let todayCR = todayHitRate >= 1 ? 1_000_000 : Int(Double(todayInput) * todayHitRate / (1 - todayHitRate))
        let prevInput = 1000
        let prevCR = prevHitRate >= 1 ? 1_000_000 : Int(Double(prevInput) * prevHitRate / (1 - prevHitRate))
        return DailyUsageReport(
            today: make(input: todayInput, cacheRead: todayCR, savings: todaySavings, cacheTokens: todayCacheTokens, date: Date()),
            previous: make(input: prevInput, cacheRead: prevCR, savings: prevSavings, cacheTokens: prevCacheTokens, date: Date().addingTimeInterval(-86400))
        )
    }

    @Test func `should show the cache hit rate change in percentage points`() {
        let report = makeCacheReport(todayHitRate: 0.92, prevHitRate: 0.85)
        #expect(abs(report.cacheHitRateDelta - 0.07) < 0.001)
    }

    @Test func `should print the cache hit rate change in percentage points`() {
        let report = makeCacheReport(todayHitRate: 0.92, prevHitRate: 0.85)
        #expect(report.formattedCacheHitRateDelta == "+7.0pp")
    }

    @Test func `should print the cache savings change in dollars`() {
        let report = makeCacheReport(todayHitRate: 0.5, prevHitRate: 0.5, todaySavings: 412.30, prevSavings: 200)
        #expect(report.formattedSavingsDelta == "+$212.30")
    }

    @Test func `should print the cache token change in millions`() {
        let report = makeCacheReport(todayHitRate: 0.5, prevHitRate: 0.5, todayCacheTokens: 37_000_000, prevCacheTokens: 20_000_000)
        #expect(report.formattedCacheTokenDelta == "+17.0M")
    }

    @Test
    func `should show working time only when either day has some`() {
        let empty = DailyUsageStat(date: Date(), totalCost: 0, totalTokens: 10, workingTime: 0, sessionCount: 1)
        let worked = DailyUsageStat(date: Date(), totalCost: 0, totalTokens: 10, workingTime: 600, sessionCount: 1)
        #expect(!DailyUsageReport(today: empty, previous: empty).hasWorkingTime)
        #expect(DailyUsageReport(today: empty, previous: worked).hasWorkingTime)
    }
}
