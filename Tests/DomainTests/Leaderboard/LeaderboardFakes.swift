import Foundation
import Mockable
@testable import Domain

final class InMemorySigningKeyStore: SigningKeyStore, @unchecked Sendable {
    var stored: Data?

    func load() -> Data? { stored }
    func save(_ rawKey: Data) { stored = rawKey }
    func delete() { stored = nil }
}

final class InMemoryLeaderboardSettings: LeaderboardSettingsRepository, @unchecked Sendable {
    var record: LeaderboardRecord?

    func leaderboardRecord() -> LeaderboardRecord? { record }
    func saveLeaderboardRecord(_ record: LeaderboardRecord?) { self.record = record }
}

/// This Mac's logs: what each login used, and the range last asked for.
@MainActor
final class FakeTokenLogs: TokenLogs {
    var providersWithLogs: Set<String>
    var logins: [LoginDays] = []
    private(set) var askedFor: DateRange?

    init(providersWithLogs: Set<String> = ["claude", "codex"]) {
        self.providersWithLogs = providersWithLogs
    }

    func days(in range: DateRange) async -> [LoginDays] {
        askedFor = range
        return logins
    }
}

enum LeaderboardFixtures {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        return calendar
    }()

    static func date(_ day: Int, month: Int = 10, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    static func stat(day: Int, input: Int = 0, output: Int = 0, cacheRead: Int = 0) -> DailyUsageStat {
        DailyUsageStat(date: date(day), totalCost: 0, totalTokens: input + output, workingTime: 0, sessionCount: 1,
                       inputTokens: input, outputTokens: output, cacheReadTokens: cacheRead)
    }
}

extension MockLeaderboardAPI {
    /// A server that accepts every call.
    static func accepting() -> MockLeaderboardAPI {
        let api = MockLeaderboardAPI()
        given(api).join(username: .any, publicKey: .any).willReturn(())
        given(api).upload(.any, as: .any).willReturn(())
        given(api).update(username: .any, visible: .any, as: .any).willReturn(())
        given(api).leave(as: .any).willReturn(())
        return api
    }
}
