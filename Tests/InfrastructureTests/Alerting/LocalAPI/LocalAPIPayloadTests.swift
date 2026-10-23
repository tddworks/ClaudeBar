import Testing
import Foundation
import Quotas
@testable import Infrastructure

/// THE JSON CONTRACT, built purely from `Quotas` values. A balance with no
/// ceiling has no percentage; a quota without a forecast has no line — the
/// JSON says what the screens say, or nothing at all.
@Suite
struct LocalAPIPayloadTests {

    /// A fixed moment, so every ISO string is expected from the same clock.
    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    /// A reset two hours from the wall clock — `timeUntilReset` reads "now",
    /// so the fixture must too.
    private let resetAt = Date().addingTimeInterval(2 * 3600)

    private func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    /// A 5-hour session quota, 62% left, refilling two hours out.
    private var sessionQuota: UsageQuota {
        UsageQuota(
            percentRemaining: 62, quotaType: .session, providerId: "claude",
            resetsAt: resetAt, windowDuration: 5 * 3600
        )
    }

    @Test func `should report a share quota as its percent key name and reset`() {
        let report = QuotaReport(quota: sessionQuota, at: now)

        #expect(report.key == "session")
        #expect(report.name == "Session")
        #expect(report.percentLeft == 62)
        #expect(report.dollarRemaining == nil)
        #expect(report.resetsAt == iso(resetAt))
        #expect(report.resetsInMinutes == 120)
    }

    @Test func `should use the card's short title for the quota name when it has one`() {
        let quota = UsageQuota(
            percentRemaining: 62, quotaType: .weekly, providerId: "claude",
            compactTitle: "7d"
        )

        #expect(QuotaReport(quota: quota, at: now).name == "7d")
    }

    @Test func `should report a balance with no ceiling as money with no percentage`() {
        let balance = UsageQuota(
            left: .money(Money(50), of: nil), quotaType: .session, providerId: "kiro"
        )

        let report = QuotaReport(quota: balance, at: now)

        #expect(report.percentLeft == nil)
        #expect(report.dollarRemaining == 50)
        #expect(report.dollarCap == nil)
        #expect(report.currency == "USD")
    }

    @Test func `should report a capped money quota's share as its money's`() {
        let capped = UsageQuota(
            left: .money(Money(12.50), of: Money(50)), quotaType: .timeLimit("Spark"), providerId: "kiro"
        )

        let report = QuotaReport(quota: capped, at: now)

        #expect(report.percentLeft == 25)
        #expect(report.dollarRemaining == 12.5)
        #expect(report.dollarCap == 50)
    }

    @Test func `should carry the quota's own currency`() {
        let yuan = UsageQuota(
            left: .money(Money(110, currency: "CNY"), of: Money(200, currency: "CNY")),
            quotaType: .session, providerId: "qwen"
        )

        let report = QuotaReport(quota: yuan, at: now)

        #expect(report.currency == "CNY")
        #expect(abs((report.percentLeft ?? 0) - 55) < 0.001)
    }

    @Test func `should word the status and the summary the screens print`() {
        let lowest = LowestQuota(quota: sessionQuota, provider: "claude", login: "work", name: "Work", at: now)

        let summary = StatusSummary(status: .warning, lowest: lowest, providers: 3, at: now)

        #expect(summary.status == "warning")
        #expect(summary.summary == "62% left · warning")
        #expect(summary.lowest == lowest)
        #expect(summary.providers == 3)
        #expect(summary.updatedAt == iso(now))
    }

    @Test func `should word a summary with no lowest as the status alone`() {
        let summary = StatusSummary(status: .healthy, lowest: nil, providers: 1, at: now)

        #expect(summary.summary == "healthy")
        #expect(summary.lowest == nil)
    }

    @Test func `should name the quota about to run out first`() {
        let lowest = LowestQuota(quota: sessionQuota, provider: "claude", login: "work", name: "Work", at: now)

        #expect(lowest.provider == "claude")
        #expect(lowest.login == "work")
        #expect(lowest.name == "Work")
        #expect(lowest.quota == "Session")
        #expect(lowest.key == "session")
        #expect(lowest.percentLeft == 62)
        #expect(lowest.resetsAt == iso(resetAt))
        #expect(lowest.resetsInMinutes == 120)
    }

    @Test func `should build a forecast line that lasts until it resets`() {
        let line = ForecastLine(
            forecast: .lastsUntilReset, quota: sessionQuota,
            provider: "claude", login: "work", loginName: "Work"
        )

        #expect(line?.state == "lastsUntilReset")
        #expect(line?.runsOutInMinutes == nil)
        #expect(line?.beforeResetMinutes == nil)
        #expect(line?.quota == "Session")
        #expect(line?.key == "session")
    }

    @Test func `should build a forecast line that runs out before it resets`() {
        let line = ForecastLine(
            forecast: .runsOut(in: .seconds(2040), beforeReset: .seconds(360)), quota: sessionQuota,
            provider: "claude", login: "work", loginName: "Work"
        )

        #expect(line?.state == "runsOut")
        #expect(line?.runsOutInMinutes == 34)
        #expect(line?.beforeResetMinutes == 6)
    }

    @Test func `should group a provider's logins under its name`() {
        let report = ProvidersReport(providers: [
            ProviderReport(id: "claude", name: "Claude", logins: [
                LoginReport(
                    id: "work", name: "Work", status: .healthy, best: true, inUse: true,
                    plan: "Max 20x", source: "via RPC", updatedAt: now,
                    quotas: [QuotaReport(quota: sessionQuota, at: now)], at: now
                ),
            ]),
        ], at: now)

        #expect(report.updatedAt == iso(now))
        #expect(report.providers.count == 1)
        #expect(report.providers[0].id == "claude")
        #expect(report.providers[0].name == "Claude")

        let login = report.providers[0].logins[0]
        #expect(login.status == "healthy")
        #expect(login.best)
        #expect(login.inUse)
        #expect(login.plan == "Max 20x")
        #expect(login.source == "via RPC")
        #expect(login.updatedAt == iso(now))
        #expect(login.quotas.count == 1)
    }

    @Test func `should leave a login's plan source and update time out when nothing said them`() {
        let login = LoginReport(
            id: "free", name: "Free", status: .depleted, best: false, inUse: false,
            plan: nil, source: nil, updatedAt: nil, quotas: [], at: now
        )

        #expect(login.plan == nil)
        #expect(login.source == nil)
        #expect(login.updatedAt == nil)
        #expect(login.status == "depleted")
        #expect(!login.best)
        #expect(!login.inUse)
    }

    @Test func `should write a day as the date the login's history counts`() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var parts = DateComponents()
        parts.year = 2026; parts.month = 10; parts.day = 22; parts.hour = 23
        let date = calendar.date(from: parts)!
        let stat = DailyUsageStat(
            date: date, totalCost: 3.25, totalTokens: 900, workingTime: 1500, sessionCount: 4,
            inputTokens: 500, outputTokens: 400, cacheCreationTokens: 300, cacheReadTokens: 200
        )

        let day = DayUsage(stat: stat, knowsCost: true, calendar: calendar)

        #expect(day.date == "2026-10-22")
        #expect(day.cost == 3.25)
        #expect(day.tokens == 900)
        #expect(day.inputTokens == 500)
        #expect(day.outputTokens == 400)
        #expect(day.cacheTokens == 500)
        #expect(day.workingMinutes == 25)
        #expect(day.sessions == 4)
    }

    @Test func `should leave a day's cost out when the login's log knows no prices`() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let stat = DailyUsageStat(date: now, totalCost: 0, totalTokens: 10, workingTime: 60, sessionCount: 1)

        let day = DayUsage(stat: stat, knowsCost: false, calendar: calendar)

        #expect(day.cost == nil)
        #expect(day.workingMinutes == 1)
    }

    @Test func `should round trip the usage days report through JSON`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let stat = DailyUsageStat(date: now, totalCost: 1.5, totalTokens: 100, workingTime: 120, sessionCount: 2)
        let report = UsageDaysReport(days: 30, logins: [
            LoginDaySeries(id: "work", name: "Work", days: [DayUsage(stat: stat, knowsCost: true, calendar: calendar)]),
        ])

        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(UsageDaysReport.self, from: data)

        #expect(decoded == report)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["days"] as? Int == 30)
        #expect((object["logins"] as? [Any])?.count == 1)
    }
}
