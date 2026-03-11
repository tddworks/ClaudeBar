import Foundation
import Testing
@testable import Domain

@Suite
struct DailyUsageStatTests {
    @Test func `formats cost as USD currency`() {
        let stat = DailyUsageStat(
            date: Date(),
            totalCost: 14.26,
            totalTokens: 0,
            workingTime: 0,
            sessionCount: 0
        )
        #expect(stat.formattedCost == "$14.26")
    }

    @Test func `formats zero cost`() {
        let stat = DailyUsageStat.empty(for: Date())
        #expect(stat.formattedCost == "$0.00")
    }

    @Test func `formats large token count as millions`() {
        let stat = DailyUsageStat(
            date: Date(),
            totalCost: 0,
            totalTokens: 19_498_439,
            workingTime: 0,
            sessionCount: 0
        )
        #expect(stat.formattedTokens == "19.5M")
    }

    @Test func `formats medium token count as thousands`() {
        let stat = DailyUsageStat(
            date: Date(),
            totalCost: 0,
            totalTokens: 1_200,
            workingTime: 0,
            sessionCount: 0
        )
        #expect(stat.formattedTokens == "1.2K")
    }

    @Test func `formats small token count as raw number`() {
        let stat = DailyUsageStat(
            date: Date(),
            totalCost: 0,
            totalTokens: 500,
            workingTime: 0,
            sessionCount: 0
        )
        #expect(stat.formattedTokens == "500")
    }

    @Test func `formats working time with hours and minutes`() {
        let stat = DailyUsageStat(
            date: Date(),
            totalCost: 0,
            totalTokens: 0,
            workingTime: 80160, // 22h 16m
            sessionCount: 0
        )
        #expect(stat.formattedWorkingTime == "22h 16m")
    }

    @Test func `formats working time with minutes and seconds only`() {
        let stat = DailyUsageStat(
            date: Date(),
            totalCost: 0,
            totalTokens: 0,
            workingTime: 330, // 5m 30s
            sessionCount: 0
        )
        #expect(stat.formattedWorkingTime == "5m 30s")
    }

    @Test func `empty stat has all zeros`() {
        let stat = DailyUsageStat.empty(for: Date())
        #expect(stat.isEmpty)
        #expect(stat.totalCost == 0)
        #expect(stat.totalTokens == 0)
        #expect(stat.workingTime == 0)
    }

    @Test func `non-empty stat with tokens is not empty`() {
        let stat = DailyUsageStat(
            date: Date(),
            totalCost: 0,
            totalTokens: 100,
            workingTime: 0,
            sessionCount: 1
        )
        #expect(!stat.isEmpty)
    }
}
