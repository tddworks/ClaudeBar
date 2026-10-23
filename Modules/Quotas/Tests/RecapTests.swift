import Foundation
import Testing
@testable import Quotas

/// A recap is what a range added up to across every provider, read in the one
/// unit every range offers, against the range before it. The one read that
/// sums across logins (CANONICAL §5, `Recap`).
@Suite
struct RecapTests {
    private let monday = Date(timeIntervalSince1970: 1_760_000_000)
    private let tuesday = Date(timeIntervalSince1970: 1_760_086_400)

    private let large = ModelUsageLine(model: "acme-large-2", totalTokens: 100, cost: 12)
    private let small = ModelUsageLine(model: "acme-small-1", totalTokens: 400, cost: 2)
    /// The days a recap was read for — the range it carries.
    private let week = DateRange.last(7, endingOn: Date(timeIntervalSince1970: 1_760_086_400),
                                      calendar: Calendar(identifier: .gregorian))

    /// A day with only the fields a test names set.
    private func day(_ date: Date, cost: Decimal = 0, tokens: Int = 0, workingTime: TimeInterval = 0,
                     sessions: Int = 1, savings: Decimal = 0, lines: [ModelUsageLine] = []) -> DailyUsageStat {
        DailyUsageStat(date: date, totalCost: cost, totalTokens: tokens, workingTime: workingTime,
                       sessionCount: sessions, cachedSavings: savings, lines: lines)
    }

    private func priced(_ stats: DailyUsageStat...) -> Days { Days(stats, knowsCost: true) }
    private func unpriced(_ stats: DailyUsageStat...) -> Days { Days(stats, knowsCost: false) }

    // MARK: - The unit

    @Test func `should read in cost when every provider prices its days`() {
        let recap = Recap(range: week, this: ["a": priced(day(monday, cost: 10, tokens: 100)),
                                 "b": priced(day(monday, cost: 5, tokens: 900))], before: [:])

        #expect(recap.unit == .cost)
        #expect(recap.total == 15)
    }

    /// One unpriced provider would count as $0 in dollars, so the whole recap
    /// reads in tokens.
    @Test func `should read in tokens when one provider prices nothing`() {
        let recap = Recap(range: week, this: ["a": priced(day(monday, cost: 10, tokens: 100)),
                                 "b": unpriced(day(monday, tokens: 900))], before: [:])

        #expect(recap.unit == .tokens)
        #expect(recap.total == 1_000)
    }

    /// A priced provider that was idle this week has nothing to say, and
    /// doesn't take dollars away from the ones that were used.
    @Test func `should keep cost when an idle provider has no cost this week`() {
        let recap = Recap(range: week, this: ["a": priced(day(monday, cost: 10, tokens: 100)),
                                 "b": priced(DailyUsageStat.empty(for: monday))], before: [:])

        #expect(recap.unit == .cost)
    }

    /// The total and the week before are read in one unit, so an unpriced
    /// provider used only the week before still turns the recap to tokens.
    @Test func `should read the week before in the same unit as the week`() {
        let recap = Recap(range: week, this: ["a": priced(day(tuesday, cost: 10, tokens: 100))],
                          before: ["b": unpriced(day(monday, tokens: 50))])

        #expect(recap.unit == .tokens)
        #expect(recap.change == 1)
    }

    /// Tokens mean what the chart means: input and output, never the cache.
    @Test func `should count tokens as the chart does, cache apart`() {
        let cached = DailyUsageStat(date: monday, totalCost: 0, totalTokens: 100, workingTime: 0, sessionCount: 1,
                                    cacheCreationTokens: 50, cacheReadTokens: 5_000)

        #expect(Recap(range: week, this: ["a": unpriced(cached)], before: [:]).total == 100)
    }

    /// Beside a dollar total, the tokens are told too; beside a token total
    /// they would only repeat it.
    @Test func `should tell the tokens beside a total in dollars, and not repeat them beside tokens`() {
        let dollars = Recap(range: week, this: ["a": priced(day(monday, cost: 10, tokens: 100))], before: [:])
        let tokens = Recap(range: week, this: ["a": unpriced(day(monday, tokens: 100))], before: [:])

        #expect(dollars.tokens == 100)
        #expect(tokens.tokens == nil)
    }

    // MARK: - The change

    @Test func `should compare the week with the one before it`() {
        let recap = Recap(range: week, this: ["a": priced(day(tuesday, cost: 12))], before: ["a": priced(day(monday, cost: 10))])

        #expect(recap.change == 0.2)
    }

    @Test func `should have no change when nothing was used the week before`() {
        let recap = Recap(range: week, this: ["a": priced(day(tuesday, cost: 12))],
                          before: ["a": priced(DailyUsageStat.empty(for: monday))])

        #expect(recap.change == nil)
    }

    // MARK: - The providers

    @Test func `should name each provider with its share, largest first`() {
        let recap = Recap(range: week, this: ["b": priced(day(monday, cost: 5)), "a": priced(day(monday, cost: 15))], before: [:])

        #expect(recap.providers == [Recap.Part(provider: "a", value: 15, share: 0.75),
                                    Recap.Part(provider: "b", value: 5, share: 0.25)])
    }

    @Test func `should leave out a provider that used nothing in the week`() {
        let recap = Recap(range: week, this: ["a": priced(day(monday, cost: 15)), "b": priced(DailyUsageStat.empty(for: monday))],
                          before: [:])

        #expect(recap.providers.map(\.provider) == ["a"])
    }

    // MARK: - The highlights, read across every provider

    /// The top model is the mix's, read over every provider's days at once.
    @Test func `should name the model that spent the most across every provider`() {
        let recap = Recap(range: week, this: ["a": priced(day(monday, cost: 2, tokens: 400, lines: [small])),
                                 "b": priced(day(monday, cost: 12, tokens: 100, lines: [large]))], before: [:])

        #expect(recap.topModel?.line.model == large.model)
    }

    /// The biggest day adds every provider's day up before it compares.
    @Test func `should name the day that added up to the most across every provider`() {
        let recap = Recap(range: week, this: ["a": priced(day(monday, cost: 8), day(tuesday, cost: 6)),
                                 "b": priced(day(monday, cost: 1), day(tuesday, cost: 5))], before: [:])

        #expect(recap.biggestDay?.date == tuesday)
        #expect(recap.biggestDay?.value == 11)
    }

    @Test func `should add up the cache savings, working time and sessions of every provider`() {
        let recap = Recap(range: week, this: ["a": priced(day(monday, cost: 1, workingTime: 3_600, sessions: 2, savings: 3)),
                                 "b": priced(day(monday, cost: 1, workingTime: 600, sessions: 1, savings: 1))],
                          before: [:])

        #expect(recap.cacheSavings == 4)
        #expect(recap.workingTime == 4_200)
        #expect(recap.sessions == 3)
    }

    // MARK: - The shape, read by the report

    /// The day-by-day is `DayActivity`'s read of the merged days: every day
    /// once, oldest first, each provider's day added in.
    @Test func `should read the day by day from the merged days, oldest first`() {
        let recap = Recap(range: week, this: ["a": priced(day(monday, cost: 8), day(tuesday, cost: 6)),
                                 "b": priced(day(monday, cost: 1), day(tuesday, cost: 5))], before: [:])

        #expect(recap.days.map(\.date) == [monday, tuesday])
        #expect(recap.days.map(\.value) == [9, 11])
    }

    /// The model-by-model is the mix's read: every model, largest first.
    @Test func `should read every model from the mix, largest first`() {
        let recap = Recap(range: week, this: ["a": priced(day(monday, cost: 2, tokens: 400, lines: [small])),
                                 "b": priced(day(monday, cost: 12, tokens: 100, lines: [large]))], before: [:])

        #expect(recap.models.map(\.line.model) == [large.model, small.model])
        #expect(recap.models.map(\.value) == [12, 2])
    }

    /// A week that held nothing has no shape to read.
    @Test func `should read no days and no models when the week held nothing`() {
        let recap = Recap(range: week, this: ["a": priced(DailyUsageStat.empty(for: monday))], before: [:])

        #expect(recap.days.isEmpty)
        #expect(recap.models.isEmpty)
    }

    // MARK: - Nothing

    @Test func `should hold nothing when no provider used anything in the week`() {
        let recap = Recap(range: week, this: ["a": priced(DailyUsageStat.empty(for: monday))], before: [:])

        #expect(recap.isEmpty)
        #expect(recap.providers.isEmpty)
        #expect(recap.topModel == nil)
        #expect(recap.biggestDay == nil)
        #expect(Recap(range: week, this: [:], before: [:]).isEmpty)
    }

    // MARK: - The range

    /// A recap says which days it sums — the one answer a header and a sender read.
    @Test func `should carry the days it was read for`() {
        let recap = Recap(range: week, this: ["a": priced(day(monday, cost: 1))], before: [:])

        #expect(recap.range == week)
    }
}
