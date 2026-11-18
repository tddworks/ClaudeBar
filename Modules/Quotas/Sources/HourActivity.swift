import Foundation

/// *When in the day do I work* — every day of a range hour by hour, each hour
/// with its value in a unit and how full it is against the range's busiest
/// hour; and the range's hours of the day added up, each against the busiest
/// of them. Built from `Days`. A day whose hours were never kept is said so,
/// never drawn as twenty-four empty ones (recap design §3).
public struct HourActivity: Sendable, Equatable {
    /// One hour: its value in the unit asked, and how full it is, 0…1.
    public struct Hour: Sendable, Equatable {
        /// The hour of the day, 0…23.
        public let hour: Int
        public let value: Double
        public let share: Double
    }

    /// One day, hour by hour.
    public struct Day: Sendable, Equatable {
        /// The day, at its start.
        public let date: Date
        /// All twenty-four hours, an idle one a value of 0 — or none when
        /// the day used something and its hours aren't known.
        public let hours: [Hour]
        /// Whether the day's hours are known (`DailyUsageStat.knowsHours`).
        public let isKnown: Bool
    }

    /// Every date of the range, oldest first.
    public let days: [Day]
    /// The range's hours of the day, 0…23: each hour summed over the days
    /// that know theirs, against the busiest of the twenty-four.
    public let ofDay: [Hour]
    /// The hour used most, and its day — nil when no hour is known.
    public let busiest: (date: Date, hour: Hour)?
    /// Whether no day of the range knows an hour that held anything.
    public var isEmpty: Bool { busiest == nil }

    /// `range`'s days read hour by hour in `unit`.
    public init(of range: Days, in unit: Days.Unit) {
        let read: [(date: Date, values: [Double]?)] = range.stats.map { day in
            guard day.knowsHours else { return (day.date, nil) }
            var values = Array(repeating: 0.0, count: 24)
            for line in day.hours ?? [] where values.indices.contains(line.hour) {
                values[line.hour] += line.spend.value(in: unit)
            }
            return (day.date, values)
        }
        let most = read.compactMap { $0.values?.max() }.max() ?? 0
        days = read.map { day in
            Day(date: day.date,
                hours: (day.values ?? []).enumerated().map {
                    Hour(hour: $0.offset, value: $0.element, share: most > 0 ? $0.element / most : 0)
                },
                isKnown: day.values != nil)
        }
        let sums = (0..<24).map { hour in read.reduce(0) { $0 + ($1.values?[hour] ?? 0) } }
        let fullest = sums.max() ?? 0
        ofDay = sums.enumerated().map {
            Hour(hour: $0.offset, value: $0.element, share: fullest > 0 ? $0.element / fullest : 0)
        }
        busiest = most > 0
            ? days.lazy.compactMap { day in day.hours.first { $0.value == most }.map { (day.date, $0) } }.first
            : nil
    }

    public static func == (lhs: HourActivity, rhs: HourActivity) -> Bool {
        lhs.days == rhs.days && lhs.ofDay == rhs.ofDay
    }
}
