import Foundation
import Testing
@testable import Quotas

/// A streak is the most recent days of a range, each under a ceiling the
/// person set — counted back from the last day and stopped at the first day
/// that breaches. An empty day is not a breach, so a quiet weekend does not
/// end a streak (CANONICAL §5, `Streak`).
@Suite
struct StreakTests {
    private let first = Date(timeIntervalSince1970: 1_760_000_000)

    /// Days, oldest first, one a day, each with a cost — the unit in force.
    private func priced(_ costs: [Decimal]) -> Days {
        Days(costs.enumerated().map { offset, cost in
            DailyUsageStat(date: first.addingTimeInterval(Double(offset) * 86_400),
                           totalCost: cost, totalTokens: 0, workingTime: 0, sessionCount: 1)
        }, knowsCost: true)
    }

    /// The same, with only tokens — a login whose logs can't be priced.
    private func unpriced(_ tokens: [Int]) -> Days {
        Days(tokens.enumerated().map { offset, count in
            DailyUsageStat(date: first.addingTimeInterval(Double(offset) * 86_400),
                           totalCost: 0, totalTokens: count, workingTime: 0, sessionCount: 1)
        }, knowsCost: false)
    }

    @Test func `should count the days back from the last that each stayed under a budget`() {
        let streak = Streak(of: priced([30, 5, 10, 20]), under: .atMost(20))

        #expect(streak.length == 3)
        #expect(streak.daysInRange == 4)
        #expect(!streak.isWholeRange)
    }

    @Test func `should stop at the first day that broke the budget`() {
        let streak = Streak(of: priced([5, 5, 25, 5]), under: .atMost(20))

        #expect(streak.length == 1)
    }

    @Test func `should not treat an empty day as a breach`() {
        let streak = Streak(of: priced([5, 0, 5]), under: .atMost(20))

        #expect(streak.length == 3)
        #expect(streak.isWholeRange)
    }

    @Test func `should count every day of the range when all stayed under`() {
        let streak = Streak(of: priced([1, 2, 3]), under: .atMost(5))

        #expect(streak.length == 3)
        #expect(streak.isWholeRange)
    }

    @Test func `should read no streak when the last day broke the budget`() {
        let streak = Streak(of: priced([1, 2, 30]), under: .atMost(5))

        #expect(streak.length == 0)
        #expect(!streak.isWholeRange)
    }

    @Test func `should count against the busiest day when the ceiling is a share`() {
        let streak = Streak(of: priced([10, 4, 2, 5]), under: .share(0.5))

        #expect(streak.length == 3)
    }

    @Test func `should count the days in tokens when the range isn't priced`() {
        let streak = Streak(of: unpriced([100, 50, 80]), under: .atMost(90))

        #expect(streak.length == 2)
    }

    @Test func `should read a whole range as a streak when nothing was used at all`() {
        let streak = Streak(of: priced([0, 0, 0]), under: .share(0.5))

        #expect(streak.length == 3)
        #expect(streak.isWholeRange)
    }
}