import Foundation
import Testing
@testable import Domain

/// How an alert, or a test, reads in Slack and as JSON.
@Suite
struct WebhookBodyTests {
    private let sentAt = Date(timeIntervalSince1970: 1_792_662_060) // 2026-10-22T09:41:00Z
    private let quota = Alert.quota(QuotaAlert(login: "Claude · work", providerId: "claude", below: 35, left: 34))
    private let status = Alert.status(StatusAlert(login: "Claude · work", providerId: "claude", was: .warning, now: .critical))

    private func slackText(_ message: WebhookBody.Message) throws -> String? {
        let data = WebhookBody(message, channel: .slack, sentAt: sentAt).encoded()
        return (try JSONSerialization.jsonObject(with: data) as? [String: String])?["text"]
    }

    private func json(_ message: WebhookBody.Message) throws -> [String: Any] {
        let data = WebhookBody(message, channel: .json, sentAt: sentAt).encoded()
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Slack

    @Test func `should say in Slack which login fell below which percent and what is left`() throws {
        #expect(try slackText(.alert(quota)) == "Claude · work is below 35% — 34% left")
    }

    @Test func `should say in Slack which status a login got worse to, and from`() throws {
        #expect(try slackText(.alert(status)) == "Claude · work is critical — was warning")
    }

    @Test func `should label a test as a test in Slack`() throws {
        #expect(try slackText(.test) == "ClaudeBar test — this webhook works. No quota was judged.")
    }

    // MARK: - JSON

    @Test func `should send a quota alert as JSON with its percent and what is left`() throws {
        let body = try json(.alert(quota))

        #expect(body["type"] as? String == "quota")
        #expect(body["provider"] as? String == "claude")
        #expect(body["login"] as? String == "Claude · work")
        #expect(body["below"] as? Int == 35)
        #expect(body["left"] as? Int == 34)
        #expect(body["status"] is NSNull)
        #expect(body["was"] is NSNull)
        #expect(body["sentAt"] as? String == "2026-10-22T09:41:00Z")
    }

    @Test func `should send a status alert as JSON with the status and what it was`() throws {
        let body = try json(.alert(status))

        #expect(body["type"] as? String == "status")
        #expect(body["status"] as? String == "critical")
        #expect(body["was"] as? String == "warning")
        #expect(body["below"] is NSNull)
        #expect(body["left"] is NSNull)
    }

    @Test func `should send a test as JSON naming no login`() throws {
        let body = try json(.test)

        #expect(body["type"] as? String == "test")
        #expect(body["provider"] is NSNull)
        #expect(body["login"] is NSNull)
        #expect(body["below"] is NSNull)
        #expect(body["status"] is NSNull)
    }

    @Test(arguments: [WebhookBody.Message.test, .alert(Alert.quota(QuotaAlert(login: "C", providerId: "c", below: 1, left: 0)))])
    func `should state every key on every JSON send`(message: WebhookBody.Message) throws {
        #expect(Set(try json(message).keys) == ["type", "provider", "login", "below", "left", "status", "was", "sentAt"])
    }

    // MARK: - The recap

    /// The test's person's calendar: Gregorian, UTC, weeks from Monday.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private func date(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
    }

    private func stat(_ month: Int, _ day: Int, cost: Decimal, tokens: Int = 0,
                      models: [ModelUsageLine] = [], cacheSavings: Decimal = 0,
                      workingTime: TimeInterval = 0, sessions: Int = 0) -> DailyUsageStat {
        DailyUsageStat(date: date(month, day), totalCost: cost, totalTokens: tokens, workingTime: workingTime,
                       sessionCount: sessions, cachedSavings: cacheSavings, lines: models)
    }

    private func days(_ stats: [DailyUsageStat], knowsCost: Bool = true) -> Days {
        Days(stats, knowsCost: knowsCost)
    }

    /// The week that closed, as a recap destination is told of it.
    private func recapAlert(this: [String: Days], before: [String: Days],
                            names: [String: String], on day: Date) -> RecapAlert {
        let week = DateRange.week(containing: day, calendar: calendar)
        return RecapAlert(recap: Recap(this: this, before: before), week: week, calendar: calendar, names: names)
    }

    /// Two providers, the week before behind them: $19.92, +20%, 62/38, one
    /// top model, one biggest day, cache that saved $1.02.
    private static let fullWeek: RecapAlert = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        let week = DateRange.week(containing: calendar.date(from: DateComponents(year: 2026, month: 11, day: 3))!,
                                  calendar: calendar)
        let sonnet = ModelUsageLine(model: "claude-sonnet-4-5", cost: 12.34)
        let gpt = ModelUsageLine(model: "gpt-5-codex", cost: 7.58)
        let recap = Recap(
            this: ["claude": Days([
                DailyUsageStat(date: calendar.date(from: DateComponents(year: 2026, month: 11, day: 2))!,
                               totalCost: 7.34, totalTokens: 600, workingTime: 3_600, sessionCount: 2,
                               cachedSavings: 1.02, lines: [sonnet]),
                DailyUsageStat(date: calendar.date(from: DateComponents(year: 2026, month: 11, day: 3))!,
                               totalCost: 5, totalTokens: 400, workingTime: 7_200, sessionCount: 1,
                               lines: [sonnet]),
            ], knowsCost: true),
                   "codex": Days([
                DailyUsageStat(date: calendar.date(from: DateComponents(year: 2026, month: 11, day: 2))!,
                               totalCost: 7.58, totalTokens: 500, workingTime: 0, sessionCount: 2, lines: [gpt]),
            ], knowsCost: true)],
            before: ["claude": Days([DailyUsageStat(date: calendar.date(from: DateComponents(year: 2026, month: 10, day: 27))!,
                                                    totalCost: 9.96, totalTokens: 0, workingTime: 0, sessionCount: 0)],
                                   knowsCost: true),
                     "codex": Days([DailyUsageStat(date: calendar.date(from: DateComponents(year: 2026, month: 10, day: 27))!,
                                                   totalCost: 6.64, totalTokens: 0, workingTime: 0, sessionCount: 0)],
                                  knowsCost: true)])
        return RecapAlert(recap: recap, week: week, calendar: calendar, names: ["claude": "Claude", "codex": "Codex"])
    }()

    @Test func `should tell the week's story in Slack`() throws {
        #expect(try slackText(.recap(Self.fullWeek)) ==
            "Weekly recap Nov 2–8: $19.92, +20% vs the week before. Claude 62% · Codex 38%." +
            " Top model claude-sonnet-4-5 · biggest day Nov 2 · cache saved $1.02.")
    }

    @Test func `should leave out of the Slack line what the week doesn't have`() throws {
        let quiet = recapAlert(this: ["claude": days([stat(11, 2, cost: 12.34)])], before: [:],
                               names: ["claude": "Claude"], on: date(11, 2))

        #expect(try slackText(.recap(quiet)) == "Weekly recap Nov 2–8: $12.34. Claude 100%. Biggest day Nov 2.")
    }

    @Test func `should read a week counted in tokens, in tokens`() throws {
        let unpriced = recapAlert(this: ["claude": days([stat(11, 2, cost: 0, tokens: 19_500_000)], knowsCost: false)],
                                  before: [:], names: ["claude": "Claude"], on: date(11, 2))

        #expect(try slackText(.recap(unpriced)) == "Weekly recap Nov 2–8: 19.5M tokens. Claude 100%. Biggest day Nov 2.")
    }

    @Test func `should write the week across a month's edge both ways`() throws {
        let straddling = recapAlert(this: ["claude": days([stat(11, 30, cost: 5)])], before: [:],
                                    names: ["claude": "Claude"], on: date(11, 30))

        #expect(try slackText(.recap(straddling)) == "Weekly recap Nov 30–Dec 6: $5.00. Claude 100%. Biggest day Nov 30.")
    }

    @Test func `should write a recap's days Gregorian whatever calendar the week was read in`() throws {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = TimeZone(identifier: "UTC")!
        buddhist.firstWeekday = 2
        let week = DateRange.week(containing: date(11, 2), calendar: buddhist)
        let alert = RecapAlert(recap: Recap(this: ["claude": days([stat(11, 2, cost: 12.34)])], before: [:]),
                               week: week, calendar: buddhist, names: ["claude": "Claude"])
        let body = try json(.recap(alert))

        #expect(body["biggestDay"] as? String == "2026-11-02")
        #expect(try slackText(.recap(alert))?.contains("Nov 2–8") == true)
    }

    @Test func `should send a recap as JSON with the week's numbers`() throws {
        let body = try json(.recap(Self.fullWeek))

        #expect(body["type"] as? String == "recap")
        #expect(body["unit"] as? String == "cost")
        #expect(abs((body["total"] as? Double ?? 0) - 19.92) < 1e-9)
        #expect(abs((body["change"] as? Double ?? 0) - 0.2) < 1e-9)
        #expect(body["weekStart"] as? String == "2026-11-02T00:00:00Z")
        #expect(body["weekEnd"] as? String == "2026-11-08T00:00:00Z")
        let providers = try #require(body["providers"] as? [[String: Any]])
        #expect(providers.map { $0["provider"] as? String } == ["claude", "codex"])
        #expect(providers.first?["name"] as? String == "Claude")
        #expect(abs((providers.first?["value"] as? Double ?? 0) - 12.34) < 1e-9)
        #expect(abs((providers.first?["share"] as? Double ?? 0) - 0.62) < 0.005)
        #expect(body["topModel"] as? String == "claude-sonnet-4-5")
        #expect(body["biggestDay"] as? String == "2026-11-02")
        #expect(body["cacheSavings"] as? Double == 1.02)
        #expect(body["workingTime"] as? Double == 10_800)
        #expect(body["sessions"] as? Int == 5)
        #expect(body["tokens"] as? Double == 1_500)
        #expect(body["sentAt"] as? String == "2026-10-22T09:41:00Z")
    }

    @Test func `should write null in the recap's JSON where the week has no value`() throws {
        let quiet = recapAlert(this: ["claude": days([stat(11, 2, cost: 12.34)])], before: [:],
                               names: ["claude": "Claude"], on: date(11, 2))
        let body = try json(.recap(quiet))

        #expect(body["change"] is NSNull)
        #expect(body["topModel"] is NSNull)
        #expect(body["biggestDay"] as? String == "2026-11-02")
        #expect(body["cacheSavings"] as? Double == 0)
    }

    @Test func `should state every recap key on every recap send`() throws {
        let keys = Set(try json(.recap(Self.fullWeek)).keys)

        #expect(keys == ["type", "unit", "total", "change", "weekStart", "weekEnd", "providers",
                         "topModel", "biggestDay", "cacheSavings", "workingTime", "sessions", "tokens", "sentAt"])
    }
}
