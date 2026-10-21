import Foundation
import Testing
@testable import Quotas

/// A range of days answers the page's questions — which models, in order; a
/// day's lines, largest first; its total in a unit — so the view renders and
/// never decides (CANONICAL §5, `Days`).
@Suite
struct DaysTests {
    private let date = Date(timeIntervalSince1970: 1_760_000_000)

    private func day(_ cost: Decimal, lines: [ModelUsageLine], tokens: Int = 0) -> DailyUsageStat {
        DailyUsageStat(date: date, totalCost: cost, totalTokens: tokens, workingTime: 0, sessionCount: 1, lines: lines)
    }

    private let opus = ModelUsageLine(model: "claude-opus-4-6", inputTokens: 100, totalTokens: 120, cost: 12)
    private let sonnet = ModelUsageLine(model: "claude-sonnet-5", inputTokens: 300, totalTokens: 400, cost: 2)
    private let unnamed = ModelUsageLine(model: "", totalTokens: 50, cost: 1)

    @Test func `should name the days' models in name order, the unnamed line apart`() {
        let days = Days([day(15, lines: [sonnet, unnamed, opus]), day(0, lines: [opus])], knowsCost: true)

        #expect(days.models == ["claude-opus-4-6", "claude-sonnet-5"])
        #expect(days.hasModels)
    }

    @Test func `should offer no model split when no day names a model`() {
        let days = Days([day(5, lines: [unnamed]), day(3, lines: [])], knowsCost: true)

        #expect(days.models.isEmpty)
        #expect(!days.hasModels)
    }

    @Test func `should read a day's lines largest first by the unit in force`() {
        let mixed = day(15, lines: [sonnet, unnamed, opus])
        let priced = Days([mixed], knowsCost: true)
        #expect(priced.lines(of: mixed).map(\.model) == ["claude-opus-4-6", "claude-sonnet-5", ""])

        let tokened = day(0, lines: [opus, sonnet], tokens: 0)
        let unpriced = Days([tokened], knowsCost: false)
        #expect(unpriced.lines(of: tokened).map(\.model) == ["claude-sonnet-5", "claude-opus-4-6"])
    }

    @Test func `should total the days in the unit in force`() {
        let priced = Days([day(15, lines: [opus]), day(3, lines: [sonnet])], knowsCost: true)
        #expect(priced.total == 18)

        let unpriced = Days([day(0, lines: [opus], tokens: 500), day(0, lines: [sonnet], tokens: 250)],
                            knowsCost: false)
        #expect(unpriced.total == 750)
    }

    @Test func `should read a day's total in the unit in force`() {
        let mixed = day(15, lines: [opus, unnamed], tokens: 900)
        #expect(Days([mixed], knowsCost: true).value(of: mixed) == 15)
        #expect(Days([mixed], knowsCost: false).value(of: mixed) == 900)
    }

    // MARK: - Insights: what the shape of the range says

    private let second = Date(timeIntervalSince1970: 1_760_086_400)
    private let third = Date(timeIntervalSince1970: 1_760_172_800)

    private func spent(_ cost: Decimal, on date: Date, tokens: Int = 0,
                       working: TimeInterval = 0, savings: Decimal = 0,
                       lines: [ModelUsageLine] = []) -> DailyUsageStat {
        DailyUsageStat(date: date, totalCost: cost, totalTokens: tokens, workingTime: working,
                       sessionCount: 1, cachedSavings: savings, lines: lines)
    }

    @Test func `should total a range of days in the unit asked for`() {
        let days = Days([spent(15, on: date, tokens: 900, working: 3600),
                         spent(3, on: second, tokens: 250, working: 1800)], knowsCost: true)

        #expect(days.total(in: .cost) == 18)
        #expect(days.total(in: .tokens) == 1150)
        #expect(days.total(in: .workingTime) == 5400)
    }

    @Test func `should read a range in cost when a day's cost means anything, tokens when it doesn't`() {
        #expect(Days([spent(1, on: date)], knowsCost: true).unit == .cost)
        #expect(Days([spent(0, on: date, tokens: 5)], knowsCost: false).unit == .tokens)
    }

    @Test func `should sum each model over the range, largest first`() {
        let days = Days([spent(14, on: date, lines: [opus, sonnet]),
                         spent(2, on: second, lines: [sonnet])], knowsCost: true)

        #expect(days.byModel.map(\.model) == ["claude-opus-4-6", "claude-sonnet-5"])
        #expect(days.byModel.first?.cost == 12)
        #expect(days.byModel.last?.cost == 4)
        #expect(days.byModel.last?.totalTokens == 800)
    }

    @Test func `should keep the unnamed line in the mix, so the parts add up to the range`() {
        let days = Days([spent(13, on: date, lines: [opus, unnamed])], knowsCost: true)

        #expect(days.byModel.map(\.model) == ["claude-opus-4-6", ""])
        #expect(days.byModel.reduce(Decimal(0)) { $0 + $1.cost } == 13)
    }

    @Test func `should read the mix in tokens when the days aren't priced`() {
        let days = Days([spent(0, on: date, tokens: 700, lines: [opus, sonnet])], knowsCost: false)

        #expect(days.byModel.map(\.model) == ["claude-sonnet-5", "claude-opus-4-6"])
        #expect(days.byModel.first?.totalTokens == 400)
    }

    @Test func `should read a model's part of the range as a share of the whole`() {
        let big = ModelUsageLine(model: "claude-opus-4-6", totalTokens: 300, cost: 3)
        let small = ModelUsageLine(model: "claude-sonnet-5", totalTokens: 100, cost: 1)
        let days = Days([spent(4, on: date, lines: [big, small])], knowsCost: true)

        #expect(days.share(of: big) == 0.75)
        #expect(days.share(of: small) == 0.25)
        #expect(Days([], knowsCost: true).share(of: big) == 0)
    }

    @Test func `should add up what the cache saved over the range`() {
        let days = Days([spent(1, on: date, savings: Decimal(string: "0.25")!),
                         spent(2, on: second, savings: Decimal(string: "1.75")!)], knowsCost: true)

        #expect(days.cacheSavings == 2)
        #expect(days.formattedCacheSavings == "$2.00")
    }

    @Test func `should give every day of the range a cell, empty days included`() {
        let days = Days([spent(10, on: date), spent(0, on: second), spent(5, on: third)], knowsCost: true)

        #expect(days.byDay.map(\.date) == [date, second, third])
        #expect(days.byDay.map(\.value) == [10, 0, 5])
        #expect(days.byDay.map(\.level) == [4, 0, 2])
    }

    @Test func `should read a day's cell in tokens when the days aren't priced`() {
        let days = Days([spent(0, on: date, tokens: 100), spent(0, on: second, tokens: 50)],
                        knowsCost: false)

        #expect(days.byDay.map(\.value) == [100, 50])
        #expect(days.byDay.map(\.level) == [4, 2])
    }

    @Test func `should give a range with nothing in it no shade`() {
        let days = Days([spent(0, on: date), spent(0, on: second)], knowsCost: true)

        #expect(days.byDay.map(\.level) == [0, 0])
    }
}
