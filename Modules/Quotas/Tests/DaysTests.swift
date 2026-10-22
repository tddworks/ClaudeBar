import Foundation
import Testing
@testable import Quotas

/// A range of days answers the page's questions — which models, in order; a
/// day's lines, largest first; its total in the unit asked; which units it
/// offers — so the view renders and never decides (CANONICAL §5, `Days`).
@Suite
struct DaysTests {
    private let date = Date(timeIntervalSince1970: 1_760_000_000)

    private func day(_ cost: Decimal, lines: [ModelUsageLine], tokens: Int = 0,
                     cacheWrite: Int = 0, cacheRead: Int = 0) -> DailyUsageStat {
        DailyUsageStat(date: date, totalCost: cost, totalTokens: tokens, workingTime: 0, sessionCount: 1,
                       cacheCreationTokens: cacheWrite, cacheReadTokens: cacheRead, lines: lines)
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

    @Test func `should read a day's lines largest first in the unit asked`() {
        let mixed = day(15, lines: [sonnet, unnamed, opus])

        #expect(Days([mixed], knowsCost: true).lines(of: mixed, in: .cost).map(\.model)
            == ["claude-opus-4-6", "claude-sonnet-5", ""])
        #expect(Days([mixed], knowsCost: true).lines(of: mixed, in: .tokens).map(\.model)
            == ["claude-sonnet-5", "claude-opus-4-6", ""])
    }

    @Test func `should total the days in the unit asked`() {
        let days = Days([day(15, lines: [opus], tokens: 900, cacheWrite: 10, cacheRead: 40),
                         day(3, lines: [sonnet], tokens: 100, cacheWrite: 5, cacheRead: 20)], knowsCost: true)

        #expect(days.total(in: .cost) == 18)
        #expect(days.total(in: .tokens) == 1000)
        #expect(days.total(in: .cache) == 75)
    }

    @Test func `should read a day's total in the unit asked`() {
        let mixed = day(15, lines: [opus, unnamed], tokens: 900, cacheWrite: 10, cacheRead: 40)
        let days = Days([mixed], knowsCost: true)

        #expect(days.value(of: mixed, in: .cost) == 15)
        #expect(days.value(of: mixed, in: .tokens) == 900)
        #expect(days.value(of: mixed, in: .cache) == 50)
    }

    @Test func `should read a line's part in the unit asked`() {
        let line = ModelUsageLine(model: "claude-opus-4-6", inputTokens: 100, cacheCreationTokens: 10,
                                  cacheReadTokens: 40, totalTokens: 120, cost: 12)
        let days = Days([day(12, lines: [line], tokens: 120)], knowsCost: true)

        #expect(days.value(of: line, in: .cost) == 12)
        #expect(days.value(of: line, in: .tokens) == 120)
        #expect(days.value(of: line, in: .cache) == 50)
    }

    @Test func `should offer cost when the log prices its records and a day holds one`() {
        let days = Days([day(15, lines: [opus]), day(0, lines: [])], knowsCost: true)

        #expect(days.hasCost)
        #expect(days.units == [.cost, .tokens, .cache])
        #expect(days.defaultUnit == .cost)
    }

    @Test func `should offer no cost when no day holds one, and count tokens instead`() {
        let days = Days([day(0, lines: [opus], tokens: 900), day(0, lines: [])], knowsCost: true)

        #expect(!days.hasCost)
        #expect(days.units == [.tokens, .cache])
        #expect(days.defaultUnit == .tokens)
    }

    @Test func `should offer no cost when the log prices nothing`() {
        let days = Days([day(0, lines: [opus], tokens: 900)], knowsCost: false)

        #expect(!days.hasCost)
        #expect(days.units == [.tokens, .cache])
    }

    @Test func `should add up what the cache saved over the range`() {
        let saved = { (savings: String) in
            DailyUsageStat(date: self.date, totalCost: 1, totalTokens: 0, workingTime: 0, sessionCount: 1,
                           cachedSavings: Decimal(string: savings)!)
        }

        #expect(Days([saved("0.25"), saved("1.75")], knowsCost: true).cacheSavings == 2)
    }

    @Test func `should keep the last days of a range, oldest first`() {
        let older = day(1, lines: [], tokens: 1)
        let newer = day(2, lines: [], tokens: 2)
        let newest = day(3, lines: [], tokens: 3)

        let last = Days([older, newer, newest], knowsCost: true).last(2)

        #expect(last.stats.map(\.totalCost) == [2, 3])
        #expect(last.knowsCost)
    }

    @Test func `should hold nothing when every day is empty`() {
        let idle = DailyUsageStat.empty(for: date)

        #expect(Days([idle], knowsCost: true).isEmpty)
        #expect(!Days([idle, day(1, lines: [], tokens: 10)], knowsCost: true).isEmpty)
    }

    @Test func `should add up the working time and sessions of the range`() {
        let worked = { (seconds: TimeInterval, sessions: Int) in
            DailyUsageStat(date: self.date, totalCost: 0, totalTokens: 1, workingTime: seconds, sessionCount: sessions)
        }

        let days = Days([worked(3_600, 2), worked(600, 1)], knowsCost: true)

        #expect(days.workingTime == 4_200)
        #expect(days.sessions == 3)
    }

    /// Several ranges read as one: a date's days add up, every date kept once,
    /// oldest first.
    @Test func `should read several ranges as one, adding up each date`() {
        let tomorrow = date.addingTimeInterval(86_400)
        let first = Days([day(2, lines: [opus], tokens: 120),
                          DailyUsageStat(date: tomorrow, totalCost: 1, totalTokens: 5, workingTime: 0, sessionCount: 1)],
                         knowsCost: true)
        let second = Days([day(3, lines: [sonnet], tokens: 400)], knowsCost: true)

        let merged = Days.merged([first, second])

        #expect(merged.stats.map(\.date) == [date, tomorrow])
        #expect(merged.stats.map(\.totalCost) == [5, 1])
        #expect(merged.stats[0].lines.map(\.model) == [opus.model, sonnet.model])
        #expect(merged.knowsCost)
    }

    /// Cost speaks for the merged range only when every range prices.
    @Test func `should know cost only when every range it reads prices its records`() {
        let priced = Days([day(2, lines: [], tokens: 1)], knowsCost: true)
        let unpriced = Days([day(0, lines: [], tokens: 1)], knowsCost: false)

        #expect(!Days.merged([priced, unpriced]).knowsCost)
    }
}
