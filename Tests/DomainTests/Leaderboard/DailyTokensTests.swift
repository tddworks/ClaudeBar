import Foundation
import Testing
@testable import Domain

@Suite
struct DailyTokensTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func stat(total: Int, input: Int = 0, output: Int = 0, cacheWrite: Int = 0, cacheRead: Int = 0) -> DailyUsageStat {
        DailyUsageStat(date: calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 9))!,
                       totalCost: 12, totalTokens: total, workingTime: 3600, sessionCount: 3,
                       inputTokens: input, outputTokens: output, cacheCreationTokens: cacheWrite, cacheReadTokens: cacheRead,
                       cachedSavings: 4)
    }

    @Test func `a day keeps its four token counts and its local date, nothing else`() {
        let tokens = DailyTokens(provider: "claude", stat: stat(total: 150, input: 100, output: 50, cacheWrite: 20, cacheRead: 900),
                                 calendar: calendar)

        #expect(tokens == DailyTokens(provider: "claude", day: "2026-10-04",
                                      input: 100, output: 50, cacheWrite: 20, cacheRead: 900, unsplit: 0))
        #expect(tokens.total == 1070)
    }

    @Test func `a log that keeps only the sum is shared as its sum`() {
        let tokens = DailyTokens(provider: "mistral", stat: stat(total: 5000), calendar: calendar)

        #expect(tokens.unsplit == 5000)
        #expect(tokens.total == 5000)
    }

    @Test func `two logins' days of one provider add up`() {
        let work = DailyTokens(provider: "claude", day: "2026-10-04", input: 1, output: 2, cacheWrite: 3, cacheRead: 4, unsplit: 5)
        let personal = DailyTokens(provider: "claude", day: "2026-10-04", input: 10, output: 20, cacheWrite: 30, cacheRead: 40, unsplit: 50)

        #expect(work.adding(personal).total == 165)
    }

    @Test func `only the given providers are summed, each one's logins per day`() {
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 9))!
        let stat = { (input: Int) in DailyUsageStat(date: day, totalCost: 0, totalTokens: input, workingTime: 0, sessionCount: 1, inputTokens: input) }
        let days = DailyTokens.summed([
            LoginDays(providerId: "claude", days: [stat(10)]),
            LoginDays(providerId: "claude", days: [stat(5)]),
            LoginDays(providerId: "codex", days: [stat(99)])
        ], providers: ["claude"], calendar: calendar)

        #expect(days.map(\.input) == [15])
        #expect(days.map(\.provider) == ["claude"])
    }

    @Test func `the wire form names each count`() throws {
        let tokens = DailyTokens(provider: "codex", day: "2026-10-04", input: 1, output: 2, cacheWrite: 3, cacheRead: 4, unsplit: 0)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(tokens)) as? [String: Any]

        #expect(Set(json?.keys.map { $0 } ?? []) == ["provider", "day", "input", "output", "cacheWrite", "cacheRead", "unsplit"])
    }
}
