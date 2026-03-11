import Foundation
import Testing
@testable import Domain

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

    @Test func `cost delta is negative when today costs less`() {
        let report = makeReport(todayCost: 14.26, prevCost: 41.73)
        #expect(report.costDelta == Decimal(string: "-27.47")!)
    }

    @Test func `cost delta is positive when today costs more`() {
        let report = makeReport(todayCost: 50, prevCost: 20)
        #expect(report.costDelta == 30)
    }

    @Test func `cost change percent is calculated relative to previous`() {
        let report = makeReport(todayCost: 14.26, prevCost: 41.73)
        let percent = report.costChangePercent!
        // 14.26 / 41.73 - 1 ≈ -65.8%
        #expect(percent < -65 && percent > -66)
    }

    @Test func `cost change percent is nil when previous is zero`() {
        let report = makeReport(todayCost: 10, prevCost: 0)
        #expect(report.costChangePercent == nil)
    }

    @Test func `formatted cost delta shows sign and currency`() {
        let report = makeReport(todayCost: 14.26, prevCost: 41.73)
        #expect(report.formattedCostDelta == "-$27.47")
    }

    @Test func `formatted cost delta shows plus for positive`() {
        let report = makeReport(todayCost: 50, prevCost: 20)
        #expect(report.formattedCostDelta == "+$30.00")
    }

    // MARK: - Token Delta

    @Test func `token delta is negative when today used fewer tokens`() {
        let report = makeReport(todayTokens: 19_498_439, prevTokens: 59_706_443)
        #expect(report.tokenDelta == -40_208_004)
    }

    @Test func `formatted token delta shows millions`() {
        let report = makeReport(todayTokens: 19_498_439, prevTokens: 59_706_443)
        #expect(report.formattedTokenDelta == "-40.2M")
    }

    @Test func `formatted token delta shows positive sign`() {
        let report = makeReport(todayTokens: 50_000_000, prevTokens: 10_000_000)
        #expect(report.formattedTokenDelta == "+40.0M")
    }

    @Test func `token change percent calculated correctly`() {
        let report = makeReport(todayTokens: 19_498_439, prevTokens: 59_706_443)
        let percent = report.tokenChangePercent!
        // (19.5M - 59.7M) / 59.7M ≈ -67.3%
        #expect(percent < -67 && percent > -68)
    }

    // MARK: - Time Delta

    @Test func `time delta is positive when today has more working time`() {
        let report = makeReport(todayTime: 80160, prevTime: 70620)
        #expect(report.timeDelta == 9540) // +2h 39m
    }

    @Test func `formatted time delta shows hours and minutes`() {
        let report = makeReport(todayTime: 80160, prevTime: 70620)
        #expect(report.formattedTimeDelta == "+2h 39m")
    }

    @Test func `formatted time delta shows negative`() {
        let report = makeReport(todayTime: 3600, prevTime: 7200)
        #expect(report.formattedTimeDelta == "-1h 0m")
    }

    @Test func `time change percent calculated correctly`() {
        let report = makeReport(todayTime: 80160, prevTime: 70620)
        let percent = report.timeChangePercent!
        // 9540 / 70620 ≈ 13.5%
        #expect(percent > 13 && percent < 14)
    }

    // MARK: - Progress

    @Test func `cost progress is ratio of today to total`() {
        let report = makeReport(todayCost: 25, prevCost: 75)
        #expect(report.costProgress == 0.25)
    }

    @Test func `token progress is ratio of today to total`() {
        let report = makeReport(todayTokens: 1000, prevTokens: 3000)
        #expect(report.tokenProgress == 0.25)
    }

    @Test func `progress is zero when both are zero`() {
        let report = makeReport(todayCost: 0, todayTokens: 0, todayTime: 0, prevCost: 0, prevTokens: 0, prevTime: 0)
        #expect(report.costProgress == 0)
        #expect(report.tokenProgress == 0)
        #expect(report.timeProgress == 0)
    }
}
