import Foundation
import Testing
@testable import Quotas

/// What a range looks like day by day: every date with its value in the unit
/// asked and its share against the busiest day; an empty range has no busiest
/// day (CANONICAL §5, `DayActivity`).
@Suite
struct DayActivityTests {
    private let first = Date(timeIntervalSince1970: 1_760_000_000)
    private let second = Date(timeIntervalSince1970: 1_760_086_400)
    private let third = Date(timeIntervalSince1970: 1_760_172_800)

    private func day(_ date: Date, cost: Decimal = 0, tokens: Int = 0) -> DailyUsageStat {
        DailyUsageStat(date: date, totalCost: cost, totalTokens: tokens, workingTime: 0, sessionCount: 1)
    }

    @Test func `should give every date of the range a value, empty days included`() {
        let days = Days([day(first, cost: 10), day(second), day(third, cost: 5)], knowsCost: true)

        let activity = DayActivity(of: days, in: .cost)

        #expect(activity.days.map(\.date) == [first, second, third])
        #expect(activity.days.map(\.value) == [10, 0, 5])
    }

    @Test func `should read each day as a share of the busiest`() {
        let days = Days([day(first, cost: 10), day(second), day(third, cost: 5)], knowsCost: true)

        #expect(DayActivity(of: days, in: .cost).days.map(\.share) == [1, 0, 0.5])
    }

    @Test func `should read the days in the unit asked`() {
        let days = Days([day(first, cost: 1, tokens: 100), day(second, cost: 9, tokens: 50)], knowsCost: true)

        let activity = DayActivity(of: days, in: .tokens)

        #expect(activity.days.map(\.value) == [100, 50])
        #expect(activity.busiest?.date == first)
    }

    @Test func `should name the busiest day`() {
        let days = Days([day(first, cost: 2), day(second, cost: 7), day(third, cost: 3)], knowsCost: true)

        #expect(DayActivity(of: days, in: .cost).busiest == DayValue(date: second, value: 7, share: 1))
    }

    @Test func `should have no busiest day and no share when nothing was used`() {
        let activity = DayActivity(of: Days([day(first), day(second)], knowsCost: true), in: .cost)

        #expect(activity.busiest == nil)
        #expect(activity.days.map(\.share) == [0, 0])
    }
}
