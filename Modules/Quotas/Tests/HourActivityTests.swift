import Foundation
import Testing
@testable import Quotas

/// *When in the day do I work* — a range's days hour by hour, each hour
/// against the range's busiest, and the hours of the day added up. A day
/// whose hours were never kept is said so (recap design §3).
@Suite
struct HourActivityTests {
    private let monday = Date(timeIntervalSince1970: 1_760_000_000)
    private let tuesday = Date(timeIntervalSince1970: 1_760_086_400)

    private func hour(_ hour: Int, cost: Decimal, tokens: Int = 0) -> HourUsageLine {
        HourUsageLine(hour: hour, spend: Spend(totalTokens: tokens, cost: cost))
    }

    private func day(_ date: Date, cost: Decimal, tokens: Int = 0, hours: [HourUsageLine]?) -> DailyUsageStat {
        DailyUsageStat(date: date, totalCost: cost, totalTokens: tokens, workingTime: 0, sessionCount: 1,
                       hours: hours.map(DayHours.known) ?? .notRead)
    }

    @Test func `should read every hour of a day, an idle one as nothing`() {
        let activity = HourActivity(of: Days([day(monday, cost: 6, hours: [hour(9, cost: 4), hour(14, cost: 2)])],
                                             knowsCost: true), in: .cost)

        #expect(activity.days[0].hours.count == 24)
        #expect(activity.days[0].hours[9].value == 4)
        #expect(activity.days[0].hours[10].value == 0)
    }

    @Test func `should tell how full an hour is against the busiest hour of the range`() {
        let activity = HourActivity(of: Days([day(monday, cost: 4, hours: [hour(9, cost: 4)]),
                                              day(tuesday, cost: 8, hours: [hour(9, cost: 8)])], knowsCost: true), in: .cost)

        #expect(activity.days[0].hours[9].share == 0.5)
        #expect(activity.busiest?.date == tuesday)
        #expect(activity.busiest?.hour.hour == 9)
    }

    @Test func `should add up each hour of the day over the range`() {
        let activity = HourActivity(of: Days([day(monday, cost: 6, hours: [hour(9, cost: 4), hour(14, cost: 2)]),
                                              day(tuesday, cost: 4, hours: [hour(9, cost: 4)])], knowsCost: true), in: .cost)

        #expect(activity.ofDay[9].value == 8)
        #expect(activity.ofDay[9].share == 1)
        #expect(activity.ofDay[14].share == 0.25)
    }

    @Test func `should read the hours in the unit asked`() {
        let activity = HourActivity(of: Days([day(monday, cost: 4, tokens: 900, hours: [hour(9, cost: 4, tokens: 900)])],
                                             knowsCost: true), in: .tokens)

        #expect(activity.days[0].hours[9].value == 900)
    }

    /// A day kept before hours were: it used something, and nothing says when.
    @Test func `should say a day's hours are not known when it was never split by hour`() {
        let activity = HourActivity(of: Days([day(monday, cost: 4, hours: nil),
                                              day(tuesday, cost: 2, hours: [hour(9, cost: 2)])], knowsCost: true), in: .cost)

        #expect(activity.days.map(\.isKnown) == [false, true])
        #expect(activity.days[0].hours.isEmpty)
        #expect(activity.ofDay[9].value == 2)
    }

    @Test func `should know an idle day's hours: none`() {
        let activity = HourActivity(of: Days([DailyUsageStat.empty(for: monday)], knowsCost: true), in: .cost)

        #expect(activity.days[0].isKnown)
        #expect(activity.isEmpty)
    }

    /// Two logins' days as one: an hour both worked in adds up.
    @Test func `should add two days' hours into one when the days add up`() {
        let sum = day(monday, cost: 4, hours: [hour(9, cost: 4)]) + day(monday, cost: 3, hours: [hour(9, cost: 1), hour(11, cost: 2)])

        #expect(sum.hours == .known([hour(9, cost: 5), hour(11, cost: 2)]))
    }

    /// Half a day's hours would read as the whole day's.
    @Test func `should not know a sum's hours when one of its days never kept its own`() {
        let sum = day(monday, cost: 4, hours: [hour(9, cost: 4)]) + day(monday, cost: 3, hours: nil)

        #expect(!sum.knowsHours)
        #expect(sum.needsHoursRead)
    }

    @Test func `should name the busiest hour and its day`() {
        let activity = HourActivity(of: Days([day(monday, cost: 4, hours: [hour(9, cost: 4)])], knowsCost: true), in: .cost)

        #expect(activity.busiest == HourActivity.Peak(date: monday, hour: HourActivity.Hour(hour: 9, value: 4, share: 1)))
    }

    // MARK: - What a day knows of its hours

    /// A day that used nothing knows its hours — none — however it is built.
    @Test func `should know an idle day's hours whatever it was told`() {
        #expect(DailyUsageStat.empty(for: monday).hours == .known([]))
        #expect(DailyUsageStat.empty(for: monday).with(hours: .notKept).hours == .known([]))
        #expect(!DailyUsageStat.empty(for: monday).needsHoursRead)
    }

    @Test func `should need its hours read only when it was never asked`() {
        #expect(day(monday, cost: 4, hours: nil).needsHoursRead)
        #expect(!day(monday, cost: 4, hours: nil).with(hours: .notKept).needsHoursRead)
        #expect(!day(monday, cost: 4, hours: [hour(9, cost: 4)]).needsHoursRead)
    }

    /// A day whose logs were cleared says so when kept, and is not asked again.
    @Test func `should keep that a day's hours were not kept when it is written and read back`() throws {
        let cleared = day(monday, cost: 4, hours: nil).with(hours: .notKept)
        let read = try JSONDecoder().decode(DailyUsageStat.self, from: JSONEncoder().encode(cleared))

        #expect(read.hours == .notKept)
        #expect(!read.knowsHours)
    }

    @Test func `should not know a sum's hours when one of its days' were not kept`() {
        let sum = day(monday, cost: 4, hours: [hour(9, cost: 4)]) + day(monday, cost: 3, hours: nil).with(hours: .notKept)

        #expect(sum.hours == .notKept)
    }

    /// An idle day kept before hours were is written back as it was read.
    @Test func `should write an idle day as it was read`() throws {
        let data = try JSONEncoder().encode(DailyUsageStat.empty(for: monday))

        #expect(!String(decoding: data, as: UTF8.self).contains("hours"))
    }

    @Test func `should write a day never split by hour as it was read`() throws {
        let before = day(monday, cost: 4, hours: nil)
        let data = try JSONEncoder().encode(before)

        #expect(!String(decoding: data, as: UTF8.self).contains("hours"))
        #expect(try JSONDecoder().decode(DailyUsageStat.self, from: data) == before)
    }

    @Test func `should keep a day's hours when it is written and read back`() throws {
        let kept = day(monday, cost: 6, hours: [hour(9, cost: 4), hour(14, cost: 2)])

        #expect(try JSONDecoder().decode(DailyUsageStat.self, from: JSONEncoder().encode(kept)) == kept)
    }
}
