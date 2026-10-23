import Foundation
import Testing
@testable import Domain

/// A webhook wants an alert when it is on, sends that kind, and the alert's
/// provider is in its scope; it wants the week's recap when it is on and
/// sends recaps — the recap names no login, so scope is never judged.
@Suite
struct WebhookTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private let quota = Alert.quota(QuotaAlert(login: "Claude · work", providerId: "claude", below: 35, left: 34))
    private let status = Alert.status(StatusAlert(login: "Codex", providerId: "codex", was: .warning, now: .critical))
    private let recap: RecapAlert = {
        let calendar = Calendar(identifier: .gregorian)
        let week = DateRange(first: calendar.date(from: DateComponents(year: 2026, month: 11, day: 2))!,
                             last: calendar.date(from: DateComponents(year: 2026, month: 11, day: 8))!, calendar: calendar)
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 3))!
        let recap = Recap(this: ["claude": Days([DailyUsageStat(date: day, totalCost: 10, totalTokens: 10,
                                                                workingTime: 0, sessionCount: 1)], knowsCost: true)],
                          before: [:])
        return RecapAlert(recap: recap, week: week, calendar: calendar, names: [:])
    }()

    private func webhook(scope: Webhook.Scope = .everyLogin, quotaAlerts: Bool = true,
                         statusAlerts: Bool = true, recap: Bool = false, isOn: Bool = true) -> Webhook {
        Webhook(id: "1", name: "#ai-quota", channel: .slack, scope: scope,
                sends: Webhook.Sends(quotaAlerts: quotaAlerts, statusAlerts: statusAlerts, recap: recap), isOn: isOn)
    }

    @Test func `should want every alert when it sends both kinds for every login`() {
        #expect(webhook().wants(quota))
        #expect(webhook().wants(status))
    }

    @Test func `should want nothing while it is off`() {
        #expect(!webhook(isOn: false).wants(quota))
        #expect(!webhook(isOn: false).wants(status))
    }

    @Test func `should want only the kinds it sends`() {
        #expect(!webhook(quotaAlerts: false).wants(quota))
        #expect(webhook(quotaAlerts: false).wants(status))
        #expect(!webhook(statusAlerts: false).wants(status))
    }

    @Test func `should want only alerts about its provider's logins`() {
        #expect(webhook(scope: .provider("claude")).wants(quota))
        #expect(!webhook(scope: .provider("claude")).wants(status))
    }

    // MARK: - The recap

    @Test func `should want the recap when it is on and sends recaps`() {
        #expect(webhook(recap: true).wants(recap))
    }

    @Test func `should want no recap while it is off or sends no recaps`() {
        #expect(!webhook(recap: true, isOn: false).wants(recap))
        #expect(!webhook().wants(recap))
    }

    @Test func `should want the recap whatever its scope, since the recap names no login`() {
        #expect(webhook(scope: .provider("codex"), recap: true).wants(recap))
    }

    @Test func `should treat a recap-only webhook as sending something`() {
        #expect(!Webhook.Sends(quotaAlerts: false, statusAlerts: false, recap: true).isNothing)
        #expect(Webhook.Sends(quotaAlerts: false, statusAlerts: false, recap: false).isNothing)
    }

    @Test func `should send no recap until the person asks for it`() {
        #expect(!Webhook.Sends(quotaAlerts: true, statusAlerts: false).recap)
    }

    @Test func `should start with nothing sent`() {
        #expect(webhook().delivery == .neverSent)
    }
}
