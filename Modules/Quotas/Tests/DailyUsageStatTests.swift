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

    /// A day's project split rides with the day; days kept before it decode
    /// with none.
    @Test func `should decode a day kept before projects were recorded without them`() throws {
        let json = #"{"date":760000000,"totalCost":1.5,"totalTokens":1200,"workingTime":600,"sessionCount":2}"#
        let day = try JSONDecoder().decode(DailyUsageStat.self, from: Data(json.utf8))

        #expect(day.projects.isEmpty)
    }

    @Test func `should decode a day's project lines`() throws {
        let json = #"{"date":760000000,"totalCost":1.5,"totalTokens":1200,"workingTime":600,"sessionCount":2,"projects":[{"project":"marron","inputTokens":1000,"outputTokens":200,"cacheCreationTokens":0,"cacheReadTokens":0,"totalTokens":1200,"cost":1.5}]}"#
        let day = try JSONDecoder().decode(DailyUsageStat.self, from: Data(json.utf8))

        #expect(day.projects == [
            ProjectUsageLine(project: "marron", inputTokens: 1000, outputTokens: 200, totalTokens: 1200, cost: 1.5),
        ])
    }

    /// A day kept before the split is written exactly as it was read, so a
    /// ledger's kept days read the same and are never summed again for it.
    @Test func `should write a kept day back byte for byte`() throws {
        let kept = #"{"cacheCreationTokens":0,"cacheReadTokens":40,"cachedSavings":0.25,"date":760000000,"inputTokens":1000,"lines":[{"cacheCreationTokens":0,"cacheReadTokens":40,"cost":1.5,"inputTokens":1000,"model":"m-large","outputTokens":200,"totalTokens":1200}],"outputTokens":200,"sessionCount":2,"totalCost":1.5,"totalTokens":1200,"workingTime":600}"#
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let day = try JSONDecoder().decode(DailyUsageStat.self, from: Data(kept.utf8))

        #expect(String(decoding: try encoder.encode(day), as: UTF8.self) == kept)
    }

    @Test func `should write a day's named project lines flat, as a model's line is`() throws {
        let day = DailyUsageStat(date: Date(timeIntervalSinceReferenceDate: 760_000_000), totalCost: 1.5,
                                 totalTokens: 1200, workingTime: 0, sessionCount: 1,
                                 projects: [ProjectUsageLine(project: "marron", totalTokens: 1200, cost: 1.5)])
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let json = String(decoding: try encoder.encode(day), as: UTF8.self)

        #expect(json.contains(#""projects":[{"cacheCreationTokens":0,"cacheReadTokens":0,"cost":1.5,"inputTokens":0,"outputTokens":0,"project":"marron","totalTokens":1200}]"#))
    }

    // MARK: - The day's project split (quota-by-project design §3)

    private let splitDate = Date(timeIntervalSince1970: 1_760_000_000)
    private let marron = ProjectUsageLine(project: "marron", inputTokens: 600, totalTokens: 600, cost: 6)
    private let api = ProjectUsageLine(project: "api", inputTokens: 200, totalTokens: 200, cost: 2)

    @Test func `should split a day into its named projects and what remains of it`() {
        let day = DailyUsageStat(date: splitDate, totalCost: 10, totalTokens: 1000, workingTime: 0, sessionCount: 1,
                                 inputTokens: 1000, projects: [api, marron])

        #expect(day.projectSplit == [
            api, marron,
            ProjectUsageLine(project: "", inputTokens: 200, totalTokens: 200, cost: 2),
        ])
    }

    @Test func `should leave no remainder when the named projects hold the whole day`() {
        let day = DailyUsageStat(date: splitDate, totalCost: 8, totalTokens: 800, workingTime: 0, sessionCount: 1,
                                 inputTokens: 800, projects: [api, marron])

        #expect(day.projectSplit == [api, marron])
    }

    @Test func `should keep no unnamed line and read the whole day as unnamed when it names no project`() {
        let day = DailyUsageStat(date: splitDate, totalCost: 10, totalTokens: 1000, workingTime: 0, sessionCount: 1,
                                 projects: [ProjectUsageLine(project: "", totalTokens: 1000, cost: 10)])

        #expect(day.projects.isEmpty)
        #expect(day.projectSplit == [ProjectUsageLine(project: "", totalTokens: 1000, cost: 10)])
    }

    @Test func `should have no project parts on a day with nothing spent`() {
        #expect(DailyUsageStat.empty(for: splitDate).projectSplit.isEmpty)
    }
}
