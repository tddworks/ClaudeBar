import Foundation
import Quotas
import Testing
@testable import DataSources

/// A day's records become one stat, and — when the log names models — a
/// line per model beside the totals (daily-usage design §1: a `Cost` with a
/// line per model, so a chart can stack by model too).
@Suite
struct DayAggregatorTests {
    private let day = Date(timeIntervalSince1970: 1_760_000_000)

    private func record(model: String?, input: Int = 0, output: Int = 0, cost: Decimal? = nil) -> LogRecord {
        LogRecord(at: day.addingTimeInterval(600), model: model, input: input, output: output, cost: cost)
    }

    @Test func `should attribute each record's tokens and cost to its model`() {
        let stat = DayAggregator.stat([
            record(model: "m-large", input: 1_000, output: 200, cost: 1.5),
            record(model: "m-small", input: 300, output: 100, cost: 0.25),
        ], on: day, sessionGap: nil, prices: nil, servedLocally: false)

        #expect(stat.lines == [
            ModelUsageLine(model: "m-large", inputTokens: 1_000, outputTokens: 200, totalTokens: 1_200, cost: 1.5),
            ModelUsageLine(model: "m-small", inputTokens: 300, outputTokens: 100, totalTokens: 400, cost: 0.25),
        ])
        #expect(stat.totalCost == 1.75)
    }

    @Test func `should order named lines before the unnamed one, each by model name`() {
        let stat = DayAggregator.stat([
            record(model: "zeta", cost: 1),
            record(model: nil, cost: 1),
            record(model: "alpha", cost: 1),
        ], on: day, sessionGap: nil, prices: nil, servedLocally: false)

        #expect(stat.lines.map(\.model) == ["alpha", "zeta", ""])
    }

    @Test func `should sum a model's records into one line`() {
        let stat = DayAggregator.stat([
            record(model: "m-large", input: 1_000, cost: 1.5),
            record(model: "m-large", output: 500, cost: 0.5),
        ], on: day, sessionGap: nil, prices: nil, servedLocally: false)

        #expect(stat.lines == [
            ModelUsageLine(model: "m-large", inputTokens: 1_000, outputTokens: 500, totalTokens: 1_500, cost: 2),
        ])
    }

    @Test func `should order lines by model name`() {
        let stat = DayAggregator.stat([
            record(model: "zeta", cost: 1),
            record(model: "alpha", cost: 1),
        ], on: day, sessionGap: nil, prices: nil, servedLocally: false)

        #expect(stat.lines.map(\.model) == ["alpha", "zeta"])
    }

    @Test func `should keep a record without a model as one unnamed line in the day`() {
        let stat = DayAggregator.stat([
            record(model: nil, input: 100, cost: 0.5),
            record(model: "m", input: 10, cost: 0.25),
        ], on: day, sessionGap: nil, prices: nil, servedLocally: false)

        #expect(stat.lines == [
            ModelUsageLine(model: "m", inputTokens: 10, totalTokens: 10, cost: 0.25),
            ModelUsageLine(model: "", inputTokens: 100, totalTokens: 100, cost: 0.5),
        ])
        #expect(stat.totalCost == 0.75)
        #expect(stat.lines.reduce(0) { $0 + $1.spend.cost } == stat.totalCost)
    }

    @Test func `should make a day's lines add up to the day`() {
        let stat = DayAggregator.stat([
            record(model: "m-large", input: 1_000, output: 200, cost: 1.5),
            record(model: "m-small", input: 300, output: 100, cost: 0.25),
        ], on: day, sessionGap: nil, prices: nil, servedLocally: false)

        #expect(stat.lines.reduce(0) { $0 + $1.spend.cost } == stat.totalCost)
        #expect(stat.lines.reduce(0) { $0 + $1.spend.totalTokens } == stat.totalTokens)
    }

    @Test func `should price a line's model the way it prices the day`() {
        let prices = PriceList.load("prices.json", from: { _ in
            """
            { "per": 1000000,
              "models": [ { "id": "m-large", "input": "3", "output": "15", "cacheWrite": "1.25", "cacheRead": "0.10" } ],
              "otherwise": { "input": "3", "output": "15", "cacheWrite": "1.25", "cacheRead": "0.10" } }
            """
        })!
        let stat = DayAggregator.stat([
            LogRecord(at: day.addingTimeInterval(600), model: "m-large", input: 1_000_000, output: 100_000),
        ], on: day, sessionGap: nil, prices: prices, servedLocally: false)

        #expect(stat.totalCost == 4.5)
        #expect(stat.lines == [
            ModelUsageLine(model: "m-large", inputTokens: 1_000_000, outputTokens: 100_000,
                           totalTokens: 1_100_000, cost: 4.5),
        ])
    }

    @Test func `should keep cache tokens on a line`() {
        let stat = DayAggregator.stat([
            LogRecord(at: day.addingTimeInterval(600), model: "m", input: 100, output: 20, cacheWrite: 30, cacheRead: 400),
        ], on: day, sessionGap: nil, prices: nil, servedLocally: false)

        #expect(stat.lines == [
            ModelUsageLine(model: "m", inputTokens: 100, outputTokens: 20,
                           cacheCreationTokens: 30, cacheReadTokens: 400, totalTokens: 120),
        ])
    }

    @Test func `should leave an empty day without lines`() {
        let stat = DayAggregator.stat([], on: day, sessionGap: nil, prices: nil, servedLocally: false)

        #expect(stat == .empty(for: day))
        #expect(stat.lines.isEmpty)
    }

    // MARK: - The day's project split (quota-by-project design §3)

    private func record(in directory: String?, input: Int = 0, output: Int = 0, cost: Decimal? = nil) -> LogRecord {
        LogRecord(at: day.addingTimeInterval(600), project: directory, input: input, output: output, cost: cost)
    }

    @Test func `should attribute each record's tokens and cost to its project`() {
        let stat = DayAggregator.stat([
            record(in: "/Users/me/workspaces/ClaudeBar/marron", input: 1_000, output: 200, cost: 1.5),
            record(in: "/Users/me/workspaces/api", input: 300, output: 100, cost: 0.25),
        ], on: day, sessionGap: nil, prices: nil, servedLocally: false)

        #expect(stat.projects == [
            ProjectUsageLine(project: "api", inputTokens: 300, outputTokens: 100, totalTokens: 400, cost: 0.25),
            ProjectUsageLine(project: "marron", inputTokens: 1_000, outputTokens: 200, totalTokens: 1_200, cost: 1.5),
        ])
    }

    @Test func `should keep no project lines when no record names a directory`() {
        let stat = DayAggregator.stat([
            record(in: nil, input: 100, cost: 0.5),
            record(in: nil, input: 10, cost: 0.25),
        ], on: day, sessionGap: nil, prices: nil, servedLocally: false)

        #expect(stat.projects.isEmpty)
    }

    @Test func `should keep records without a directory as one unnamed part of a day that names projects`() {
        let stat = DayAggregator.stat([
            record(in: "/Users/me/marron", input: 1_000, cost: 1.5),
            record(in: nil, input: 100, cost: 0.5),
        ], on: day, sessionGap: nil, prices: nil, servedLocally: false)

        #expect(stat.projectSplit == [
            ProjectUsageLine(project: "marron", inputTokens: 1_000, totalTokens: 1_000, cost: 1.5),
            ProjectUsageLine(project: "", inputTokens: 100, totalTokens: 100, cost: 0.5),
        ])
    }

    @Test func `should order a day's project lines by name, the unnamed part last`() {
        let stat = DayAggregator.stat([
            record(in: "/a/zeta", cost: 1),
            record(in: "/a/api", cost: 1),
            record(in: nil, cost: 1),
        ], on: day, sessionGap: nil, prices: nil, servedLocally: false)

        #expect(stat.projectSplit.map(\.project) == ["api", "zeta", ""])
    }

    @Test func `should read an empty directory as unnamed`() {
        let stat = DayAggregator.stat([
            record(in: "", input: 500, cost: 0.5),
        ], on: day, sessionGap: nil, prices: nil, servedLocally: false)

        #expect(stat.projects.isEmpty)
    }

    @Test func `should make a day's project lines add up to the day`() {
        let stat = DayAggregator.stat([
            record(in: "/a/marron", input: 1_000, output: 200, cost: 1.5),
            record(in: "/a/api", input: 300, output: 100, cost: 0.25),
            record(in: nil, input: 50, cost: 0.1),
        ], on: day, sessionGap: nil, prices: nil, servedLocally: false)

        #expect(stat.projectSplit.reduce(0) { $0 + $1.spend.cost } == stat.totalCost)
        #expect(stat.projectSplit.reduce(0) { $0 + $1.spend.totalTokens } == stat.totalTokens)
    }
}
