import Testing
import Foundation
import Domain
@testable import Infrastructure

/// THE CONTRACT ENCODES THE ALL PAGE'S READ. Each payload repeats what
/// `Overview` already answers — the ring it leads with, a card's status, the
/// product's best login and the one in use — and decides nothing of its own.
@MainActor
@Suite
struct OverviewPayloadTests {
    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    private func quota(_ left: Double) -> UsageQuota {
        UsageQuota(percentRemaining: left, quotaType: .session, providerId: "p")
    }

    private func login(_ id: String, _ quotas: UsageQuota..., history: UsageHistory? = nil) -> OverviewCard.Login {
        let snapshot = quotas.isEmpty ? nil : UsageSnapshot(providerId: "p", quotas: quotas, capturedAt: now)
        return OverviewCard.Login(id: id, name: id.capitalized, snapshot: snapshot,
                                  status: snapshot?.overallStatus, state: .init(),
                                  source: snapshot == nil ? nil : "API", usageHistory: history)
    }

    // MARK: - `/status`

    @Test func `should point the lowest at the product whose login with the most room runs out first`() throws {
        // Before: the lowest was the emptiest login of the lineup — Acme's
        // `work` at 0% — and an agent stopped when it could have switched.
        let overview = Overview(cards: [
            OverviewCard(id: "acme", name: "Acme", logins: [login("work", quota(0)), login("home", quota(80))]),
            OverviewCard(id: "zeta", name: "Zeta", logins: [login("zeta", quota(40))]),
        ])

        let summary = StatusSummary(overview, at: now)

        let lowest = try #require(summary.lowest)
        #expect(lowest.provider == "zeta")
        #expect(lowest.login == "zeta")
        #expect(lowest.percentLeft == 40)
        #expect(summary.status == "warning")
        #expect(summary.summary == "40% left · warning")
    }

    @Test func `should count products, not logins`() {
        let overview = Overview(cards: [
            OverviewCard(id: "acme", name: "Acme", logins: [login("work", quota(50)), login("home", quota(80))]),
            OverviewCard(id: "zeta", name: "Zeta", logins: [login("zeta", quota(40))]),
        ])

        #expect(StatusSummary(overview, at: now).providers == 2)
    }

    @Test func `should give no status while no login has numbers`() {
        let overview = Overview(cards: [OverviewCard(id: "acme", name: "Acme", logins: [login("acme")])])

        let summary = StatusSummary(overview, at: now)

        #expect(summary.status == nil)
        #expect(summary.summary == "no usage yet")
        #expect(summary.lowest == nil)
    }

    @Test func `should name a balance with no ceiling as the lowest without a percentage`() throws {
        let balance = UsageQuota(left: .money(Money(42), of: nil), quotaType: .session, providerId: "p")
        let overview = Overview(cards: [OverviewCard(id: "acme", name: "Acme", logins: [login("acme", balance)])])

        let summary = StatusSummary(overview, at: now)

        let lowest = try #require(summary.lowest)
        #expect(lowest.percentLeft == nil)
        #expect(summary.summary == "healthy")
    }

    // MARK: - `/providers`

    @Test func `should report a login with no numbers yet with no status, never healthy`() throws {
        let overview = Overview(cards: [OverviewCard(id: "acme", name: "Acme", logins: [login("work", quota(62)), login("home")])])

        let report = ProvidersReport(overview, at: now)

        let rows = try #require(report.providers.first?.logins)
        #expect(rows.map(\.status) == ["healthy", nil])
    }

    @Test func `should mark the login the product calls best and the one new sessions start with`() throws {
        let overview = Overview(cards: [OverviewCard(id: "acme", name: "Acme",
                                                     logins: [login("work", quota(20)), login("home", quota(80))],
                                                     best: "home", inUse: "work")])

        let report = ProvidersReport(overview, at: now)

        let acme = try #require(report.providers.first)
        #expect(acme.id == "acme")
        #expect(acme.name == "Acme")
        #expect(acme.logins.map(\.id) == ["work", "home"])
        #expect(acme.logins.map(\.best) == [false, true])
        #expect(acme.logins.map(\.inUse) == [true, false])
        #expect(acme.logins[0].source == "API")
        #expect(acme.logins[0].quotas.first?.percentLeft == 20)
    }

    // MARK: - `/forecast`

    @Test func `should forecast the quota that has a line and leave the one without out`() throws {
        let spent = UsageQuota(percentRemaining: 20, quotaType: .session, providerId: "p",
                               resetsAt: Date().addingTimeInterval(30 * 60), windowDuration: 5 * 3600)
        let overview = Overview(cards: [OverviewCard(id: "acme", name: "Acme", logins: [login("work", spent, quota(40))])])

        let report = ForecastReport(overview, at: now)

        let line = try #require(report.forecasts.first)
        #expect(report.forecasts.count == 1)
        #expect(line.state == "lastsUntilReset")
        #expect(line.provider == "acme")
        #expect(line.login == "work")
        #expect(line.loginName == "Work")
    }

    // MARK: - `/usage/days`

    @Test func `should read each login's own days when asked, and none for a login with no history`() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let dir = home.appendingPathComponent(".acme")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try #"{"at":\#(Date().timeIntervalSince1970),"tokens":900,"cost":1.5}"#
            .write(to: dir.appendingPathComponent("log.jsonl"), atomically: true, encoding: .utf8)
        let history = UsageHistory(log: DataSources.makeUsageLog(
            UsageLog.Definition(records: UsageLog.Records(files: "~/.acme/*.jsonl", at: "$.at",
                                                          tokens: UsageLog.Tokens(total: "$.tokens"), cost: "$.cost")),
            environment: { _ in nil }, homeDirectory: home))
        let overview = Overview(cards: [OverviewCard(id: "acme", name: "Acme", logins: [
            login("work", quota(62), history: history), login("home", quota(80)),
        ])])

        let report = await UsageDaysReport.read(overview, count: 7)

        #expect(report.days == 7)
        #expect(report.logins.map(\.id) == ["work"])
        let days = try #require(report.logins.first?.days)
        #expect(days.count == 7)
        #expect(days.map(\.tokens).reduce(0, +) == 900)
    }
}
