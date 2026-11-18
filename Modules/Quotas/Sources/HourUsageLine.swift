import Foundation

/// One hour's share of a day: the hour of the day, 0…23 in the log's own
/// calendar, and what the records written in it spent. A day keeps a line
/// only for an hour that held a record, so the lines add up to the day's
/// tokens and cost — sessions and working time span hours and are never
/// split by one (recap design §3).
public struct HourUsageLine: UsageLine, Codable {
    /// The hour of the day the records were written in, 0…23.
    public let hour: Int
    public let spend: Spend

    /// Two digits, so the lines' name order is the day's order.
    public var name: String { String(format: "%02d", hour) }

    public init(hour: Int, spend: Spend) {
        self.hour = hour
        self.spend = spend
    }

    public init(name: String, spend: Spend) {
        self.init(hour: Int(name) ?? 0, spend: spend)
    }

    /// A day's hour lines, as the day keeps them — none for a day never
    /// split by hour.
    public static func split(of day: DailyUsageStat) -> [HourUsageLine] { day.hours ?? [] }

    private enum CodingKeys: String, CodingKey { case hour }

    /// Flat, as a model's line is: the hour beside its spend's counts.
    public init(from decoder: Decoder) throws {
        hour = try decoder.container(keyedBy: CodingKeys.self).decode(Int.self, forKey: .hour)
        spend = try Spend(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hour, forKey: .hour)
        try spend.encode(to: encoder)
    }
}
