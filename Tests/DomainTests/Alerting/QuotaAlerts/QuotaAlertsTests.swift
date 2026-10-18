import Foundation
import Testing
@testable import Domain

/// *Quota alerts* (#68): the person's own percentages, told once when a
/// login falls below one, and again only after it climbs back a point.
@MainActor
@Suite
struct QuotaAlertsTests {
    private final class Told: QuotaAlertAnnouncer, @unchecked Sendable {
        var alerts: [QuotaAlert] = []
        func announce(_ alert: QuotaAlert) async { alerts.append(alert) }
    }

    private final class Kept: QuotaAlertSettingsRepository, @unchecked Sendable {
        var percents: [Int]
        init(_ percents: [Int] = []) { self.percents = percents }
        func quotaAlertPercents() -> [Int] { percents }
        func setQuotaAlertPercents(_ percents: [Int]) { self.percents = percents }
    }

    private let told = Told()

    private func alerts(_ percents: [Int], kept: Kept? = nil) -> QuotaAlerts {
        QuotaAlerts(settings: kept ?? Kept(percents), announcer: told)
    }

    private func usage(_ lefts: Left...) -> UsageSnapshot {
        UsageSnapshot(providerId: "claude",
                      quotas: lefts.map { UsageQuota(left: $0, quotaType: .session, providerId: "claude") },
                      capturedAt: Date())
    }

    private func left(_ percent: Double) -> UsageSnapshot { usage(.share(percent)) }

    // MARK: - Telling

    @Test func `should tell once when a login falls below a percentage`() async {
        let alerts = alerts([35])

        await alerts.review("claude.work", named: "Claude · work", usage: left(40))
        await alerts.review("claude.work", named: "Claude · work", usage: left(34))

        #expect(told.alerts == [QuotaAlert(login: "Claude · work", below: 35, left: 34)])
    }

    @Test func `should stay quiet while the login stays below`() async {
        let alerts = alerts([35])

        for percent in [34.0, 30, 31, 12] { await alerts.review("claude", named: "Claude", usage: left(percent)) }

        #expect(told.alerts.count == 1)
    }

    @Test func `should tell again after the login climbs back a point above`() async {
        let alerts = alerts([35])

        for percent in [34.0, 36, 33] { await alerts.review("claude", named: "Claude", usage: left(percent)) }

        #expect(told.alerts.map(\.left) == [34, 33])
    }

    @Test func `should not tell again when the login climbs back less than a point`() async {
        let alerts = alerts([35])

        for percent in [34.0, 35.5, 34] { await alerts.review("claude", named: "Claude", usage: left(percent)) }

        #expect(told.alerts.count == 1)
    }

    @Test func `should tell each percentage a login falls below, highest first`() async {
        let alerts = alerts([35, 60])

        await alerts.review("claude", named: "Claude", usage: left(30))

        #expect(told.alerts.map(\.below) == [60, 35])
    }

    @Test func `should keep each login's crossing its own`() async {
        let alerts = alerts([35])

        await alerts.review("claude", named: "Claude · me", usage: left(30))
        await alerts.review("claude.work", named: "Claude · work", usage: left(30))

        #expect(told.alerts.map(\.login) == ["Claude · me", "Claude · work"])
    }

    // MARK: - What it judges

    @Test func `should judge the lowest quota the login shows`() async {
        let alerts = alerts([35])

        await alerts.review("claude", named: "Claude", usage: usage(.share(80), .share(20)))

        #expect(told.alerts == [QuotaAlert(login: "Claude", below: 35, left: 20)])
    }

    @Test func `should judge money with a ceiling by its share`() async {
        let alerts = alerts([35])

        await alerts.review("acme", named: "Acme", usage: usage(.money(Money(10), of: Money(50))))

        #expect(told.alerts == [QuotaAlert(login: "Acme", below: 35, left: 20)])
    }

    @Test func `should never judge a balance without a ceiling`() async {
        let alerts = alerts([35])

        await alerts.review("acme", named: "Acme", usage: usage(.money(Money(1), of: nil)))
        await alerts.review("acme", named: "Acme", usage: nil)

        #expect(told.alerts.isEmpty)
    }

    // MARK: - The person's percentages

    @Test func `should keep the person's percentages highest first and save them`() throws {
        let kept = Kept()
        let alerts = alerts([], kept: kept)

        try alerts.add("35")
        try alerts.add("60%")

        #expect(alerts.percents == [60, 35])
        #expect(kept.percents == [60, 35])
    }

    @Test func `should read the saved percentages at launch`() {
        #expect(alerts([35, 60]).percents == [60, 35])
    }

    @Test func `should forget a percentage the person removes`() throws {
        let kept = Kept([35, 60])
        let alerts = alerts([], kept: kept)

        alerts.remove(35)

        #expect(alerts.percents == [60])
        #expect(kept.percents == [60])
    }

    @Test func `should refuse 20 and 0 percent because ClaudeBar already alerts there`() {
        let alerts = alerts([])

        #expect(throws: QuotaAlerts.Refusal.alreadyAlerted(20)) { try alerts.add("20") }
        #expect(throws: QuotaAlerts.Refusal.alreadyAlerted(0)) { try alerts.add("0") }
        #expect(alerts.percents.isEmpty)
    }

    @Test(arguments: ["100", "-5", "35.5", "lots", ""])
    func `should refuse anything but a whole percent from 1 to 99`(entry: String) {
        #expect(throws: QuotaAlerts.Refusal.notAPercent) { try alerts([]).add(entry) }
    }

    @Test func `should refuse a percentage already on the list`() {
        #expect(throws: QuotaAlerts.Refusal.alreadyListed(35)) { try alerts([35]).add("35") }
    }

    @Test func `should refuse a sixth percentage`() {
        #expect(throws: QuotaAlerts.Refusal.full) { try alerts([10, 30, 40, 50, 60]).add("70") }
    }
}
