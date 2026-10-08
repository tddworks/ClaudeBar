import Foundation
import Testing
@testable import Quotas

@Suite
struct DailyUsageStatTests {
    @Test func `should print a day's cost in dollars`() {
        let stat = DailyUsageStat(
            date: Date(),
            totalCost: 14.26,
            totalTokens: 0,
            workingTime: 0,
            sessionCount: 0
        )
        #expect(stat.formattedCost == "$14.26")
    }

    @Test func `should print $0.00 for a day with no cost`() {
        let stat = DailyUsageStat.empty(for: Date())
        #expect(stat.formattedCost == "$0.00")
    }

    @Test func `should print a large token count in millions`() {
        let stat = DailyUsageStat(
            date: Date(),
            totalCost: 0,
            totalTokens: 19_498_439,
            workingTime: 0,
            sessionCount: 0
        )
        #expect(stat.formattedTokens == "19.5M")
    }

    @Test func `should print a medium token count in thousands`() {
        let stat = DailyUsageStat(
            date: Date(),
            totalCost: 0,
            totalTokens: 1_200,
            workingTime: 0,
            sessionCount: 0
        )
        #expect(stat.formattedTokens == "1.2K")
    }

    @Test func `should print a small token count as it is`() {
        let stat = DailyUsageStat(
            date: Date(),
            totalCost: 0,
            totalTokens: 500,
            workingTime: 0,
            sessionCount: 0
        )
        #expect(stat.formattedTokens == "500")
    }

    @Test func `should print working time in hours and minutes`() {
        let stat = DailyUsageStat(
            date: Date(),
            totalCost: 0,
            totalTokens: 0,
            workingTime: 80160, // 22h 16m
            sessionCount: 0
        )
        #expect(stat.formattedWorkingTime == "22h 16m")
    }

    @Test func `should print working time under an hour in minutes and seconds`() {
        let stat = DailyUsageStat(
            date: Date(),
            totalCost: 0,
            totalTokens: 0,
            workingTime: 330, // 5m 30s
            sessionCount: 0
        )
        #expect(stat.formattedWorkingTime == "5m 30s")
    }

    @Test func `should count an empty day as no cost, no tokens and no working time`() {
        let stat = DailyUsageStat.empty(for: Date())
        #expect(stat.isEmpty)
        #expect(stat.totalCost == 0)
        #expect(stat.totalTokens == 0)
        #expect(stat.workingTime == 0)
    }

    @Test func `should not count a day with tokens as empty`() {
        let stat = DailyUsageStat(
            date: Date(),
            totalCost: 0,
            totalTokens: 100,
            workingTime: 0,
            sessionCount: 1
        )
        #expect(!stat.isEmpty)
    }

    // MARK: - Cache

    @Test func `should count every kind of token, cache included, in the day's total`() {
        let stat = DailyUsageStat(
            date: Date(),
            totalCost: 0,
            totalTokens: 1_500,
            workingTime: 0,
            sessionCount: 0,
            inputTokens: 1_000,
            outputTokens: 500,
            cacheCreationTokens: 2_000,
            cacheReadTokens: 8_000,
            cachedSavings: 0
        )
        #expect(stat.totalTokensWithCache == 11_500)
    }

    @Test func `should count a log's total when it keeps only the total (#198)`() {
        // Claude Desktop's buddy-tokens.json, Mistral's session totals (#198).
        let stat = DailyUsageStat(date: Date(), totalCost: 0, totalTokens: 74_422, workingTime: 0, sessionCount: 1)
        #expect(stat.totalTokensWithCache == 74_422)
        #expect(stat.formattedTotalTokensWithCache == "74.4K")
    }

    @Test func `should show the cache hit rate as cache reads out of cache reads and input`() {
        let stat = DailyUsageStat(
            date: Date(),
            totalCost: 0,
            totalTokens: 1_500,
            workingTime: 0,
            sessionCount: 0,
            inputTokens: 1_000,
            outputTokens: 500,
            cacheCreationTokens: 0,
            cacheReadTokens: 9_000,
            cachedSavings: 0
        )
        // 9000 / (9000 + 1000) = 0.9
        #expect(stat.cacheHitRate == 0.9)
    }

    @Test func `should show a zero cache hit rate when there is no input and no cache read`() {
        let stat = DailyUsageStat.empty(for: Date())
        #expect(stat.cacheHitRate == 0)
    }

    @Test func `should print the cache hit rate as a percentage`() {
        let stat = DailyUsageStat(
            date: Date(),
            totalCost: 0,
            totalTokens: 0,
            workingTime: 0,
            sessionCount: 0,
            inputTokens: 1_000,
            outputTokens: 0,
            cacheCreationTokens: 0,
            cacheReadTokens: 9_000,
            cachedSavings: 0
        )
        #expect(stat.formattedHitRate == "90.0%")
    }

    @Test func `should print cache savings in dollars`() {
        let stat = DailyUsageStat(
            date: Date(),
            totalCost: 0,
            totalTokens: 0,
            workingTime: 0,
            sessionCount: 0,
            inputTokens: 0,
            outputTokens: 0,
            cacheCreationTokens: 0,
            cacheReadTokens: 0,
            cachedSavings: Decimal(string: "412.30")!
        )
        #expect(stat.formattedSavings == "$412.30")
    }

    @Test func `should print cache writes and reads together in millions`() {
        let stat = DailyUsageStat(
            date: Date(),
            totalCost: 0,
            totalTokens: 0,
            workingTime: 0,
            sessionCount: 0,
            inputTokens: 0,
            outputTokens: 0,
            cacheCreationTokens: 12_000_000,
            cacheReadTokens: 25_000_000,
            cachedSavings: 0
        )
        #expect(stat.formattedCacheTokens == "37.0M")
    }

    @Test func `should show no cache use for a day recorded without cache counts`() {
        let stat = DailyUsageStat(
            date: Date(),
            totalCost: 5,
            totalTokens: 100,
            workingTime: 60,
            sessionCount: 1
        )
        #expect(stat.cacheReadTokens == 0)
        #expect(stat.cacheCreationTokens == 0)
        #expect(stat.cacheHitRate == 0)
        #expect(stat.cachedSavings == 0)
    }

    /// A ledger page is a cache; days kept by an older ClaudeBar must keep
    /// decoding when a field is added.
    @Test func `should decode a day kept before per-model lines existed`() throws {
        let json = #"{"date":760000000,"totalCost":1.5,"totalTokens":1200,"workingTime":600,"sessionCount":2,"inputTokens":1000,"outputTokens":200,"cacheCreationTokens":0,"cacheReadTokens":0,"cachedSavings":0}"#
        let day = try JSONDecoder().decode(DailyUsageStat.self, from: Data(json.utf8))

        #expect(day.lines.isEmpty)
        #expect(day.totalCost == 1.5)
        #expect(day.totalTokens == 1200)
    }

    @Test func `should decode a day's per-model lines`() throws {
        let json = #"{"date":760000000,"totalCost":1.5,"totalTokens":1200,"workingTime":600,"sessionCount":2,"lines":[{"model":"m-large","inputTokens":1000,"outputTokens":200,"cacheCreationTokens":0,"cacheReadTokens":0,"totalTokens":1200,"cost":1.5}]}"#
        let day = try JSONDecoder().decode(DailyUsageStat.self, from: Data(json.utf8))

        #expect(day.lines == [
            ModelUsageLine(model: "m-large", inputTokens: 1000, outputTokens: 200, totalTokens: 1200, cost: 1.5),
        ])
    }
}
