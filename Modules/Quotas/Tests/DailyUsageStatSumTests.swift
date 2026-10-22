import Foundation
import Testing
@testable import Quotas

/// Two days of one date add up to one day: every count, the cost, the time
/// and the savings, and each model's lines as one line — so several logins'
/// days read as one range never drop a field (CANONICAL §5, `DailyUsageStat`).
@Suite
struct DailyUsageStatSumTests {
    private let date = Date(timeIntervalSince1970: 1_760_000_000)
    private let large = ModelUsageLine(model: "acme-large-2", totalTokens: 100, cost: 4)
    private let small = ModelUsageLine(model: "acme-small-1", totalTokens: 50, cost: 1)

    @Test func `should add every count, the cost, the time and the savings of two days of one date`() {
        let personal = DailyUsageStat(date: date, totalCost: 4, totalTokens: 100, workingTime: 600, sessionCount: 1,
                                      inputTokens: 80, outputTokens: 20, cacheCreationTokens: 5, cacheReadTokens: 40,
                                      cachedSavings: 1)
        let work = DailyUsageStat(date: date, totalCost: 2, totalTokens: 50, workingTime: 300, sessionCount: 2,
                                  inputTokens: 30, outputTokens: 20, cacheCreationTokens: 1, cacheReadTokens: 4,
                                  cachedSavings: Decimal(string: "0.5")!)

        #expect(personal + work == DailyUsageStat(date: date, totalCost: 6, totalTokens: 150, workingTime: 900,
                                                  sessionCount: 3, inputTokens: 110, outputTokens: 40,
                                                  cacheCreationTokens: 6, cacheReadTokens: 44,
                                                  cachedSavings: Decimal(string: "1.5")!))
    }

    /// A day keeps one line per model, in name order: a model both days name
    /// is one line.
    @Test func `should keep one line per model when two days of one date add up`() {
        let personal = DailyUsageStat(date: date, totalCost: 5, totalTokens: 150, workingTime: 0, sessionCount: 1,
                                      lines: [large, small])
        let work = DailyUsageStat(date: date, totalCost: 4, totalTokens: 100, workingTime: 0, sessionCount: 1,
                                  lines: [large])

        #expect((personal + work).lines == [large + large, small])
    }
}
