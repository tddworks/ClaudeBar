import Foundation
import Quotas

/// One provider's tokens for one local calendar day on this Mac — a line on
/// the tally sheet, and everything about a day that leaves the Mac. Cost,
/// sessions, working time, models and paths can't be expressed in it.
public struct DailyTokens: Sendable, Equatable, Codable {
    public let provider: String
    /// The member's own date, `yyyy-MM-dd`.
    public let day: String
    public let input: Int
    public let output: Int
    public let cacheWrite: Int
    public let cacheRead: Int
    /// Tokens a log keeps only as a sum, without saying which kind they were.
    public let unsplit: Int

    public init(provider: String, day: String, input: Int, output: Int, cacheWrite: Int, cacheRead: Int, unsplit: Int) {
        self.provider = provider
        self.day = day
        self.input = input
        self.output = output
        self.cacheWrite = cacheWrite
        self.cacheRead = cacheRead
        self.unsplit = unsplit
    }

    /// A day of a login's usage history, kept to its token counts.
    public init(provider: String, stat: DailyUsageStat, calendar: Calendar = .current) {
        self.init(provider: provider, day: Self.day(of: stat.date, calendar: calendar),
                  input: stat.inputTokens, output: stat.outputTokens,
                  cacheWrite: stat.cacheCreationTokens, cacheRead: stat.cacheReadTokens,
                  unsplit: max(0, stat.totalTokens - stat.inputTokens - stat.outputTokens))
    }

    /// Every token the day holds — what the board ranks by.
    public var total: Int { input + output + cacheWrite + cacheRead + unsplit }

    /// The same day with another login's tokens added.
    public func adding(_ other: DailyTokens) -> DailyTokens {
        DailyTokens(provider: provider, day: day, input: input + other.input, output: output + other.output,
                    cacheWrite: cacheWrite + other.cacheWrite, cacheRead: cacheRead + other.cacheRead,
                    unsplit: unsplit + other.unsplit)
    }

    /// The days of `providers` in `logins`: each provider's logins added up
    /// per day, days without tokens left out, oldest first. What an upload
    /// sends and what its preview shows are both this.
    public static func summed(_ logins: [LoginDays], providers: Set<String>, calendar: Calendar = .current) -> [DailyTokens] {
        var byDay: [String: DailyTokens] = [:]
        for login in logins where providers.contains(login.providerId) {
            for stat in login.days {
                let tokens = DailyTokens(provider: login.providerId, stat: stat, calendar: calendar)
                let key = tokens.provider + "|" + tokens.day
                byDay[key] = byDay[key].map { $0.adding(tokens) } ?? tokens
            }
        }
        return byDay.values.filter { $0.total > 0 }.sorted { ($0.day, $0.provider) < ($1.day, $1.provider) }
    }

    public static func day(of date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// What one login on this Mac used, day by day.
public struct LoginDays: Sendable, Equatable {
    public let providerId: String
    public let days: [DailyUsageStat]

    public init(providerId: String, days: [DailyUsageStat]) {
        self.providerId = providerId
        self.days = days
    }
}

/// This Mac's token logs: which providers have them, and what each login used.
@MainActor
public protocol TokenLogs: AnyObject {
    /// Providers whose logins read daily tokens from logs — the only ones
    /// that can be shared.
    var providersWithLogs: Set<String> { get }
    func days(in range: DateRange) async -> [LoginDays]
}
