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
}
