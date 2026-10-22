import Testing
import Foundation
import Mockable
import Quotas
import Domain
@testable import Infrastructure
@testable import Providers

/// THE READING'S ANSWERS, from a stubbed Monitor. The reading never refreshes
/// and never decides: it builds the JSON contract out of exactly what the
/// Monitor's reads answer — or leaves the field out, as the screens do. The
/// product is always stubbed away (`product(of:)` → nil): which login is
/// `best` or `inUse` is the product's answer to repeat, never the reading's
/// to invent.
@MainActor
@Suite
struct MonitorLocalAPIReadingTests {

    // MARK: - Fixtures

    /// A watched login, born the way the Providers module births every
    /// account: a definition, saved settings, a login.
    private func login(provider: String = "claude",
                       accountId: String = ProviderAccount.defaultAccountId,
                       label: String = "Work") -> Account {
        let json = """
        {"profile":{"id":"\(provider)","name":"Claude","links":{}},
         "dataSources":[{"kind":"stub","credential":{"environment":"STUB_READY"},
                         "fetch":{"http":{"url":"https://stub.invalid/\(provider)"}},"mapping":{"usage":{}}}],
         "defaultDataSource":"stub"}
        """
        let settings = MockProviderSettingsRepository()
        given(settings).isOn(.any, forProvider: .any).willReturn(nil)
        given(settings).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        return Account(
            definition: try! ProviderDefinition.parse(Data(json.utf8), origin: .custom),
            settings: settings,
            login: ProviderAccount(accountId: accountId, providerId: provider, label: label),
            values: [:]
        )
    }

    /// A 5-hour session quota, spent fast — 20% left, refilling half an hour
    /// out. It has a share and a forecast line.
    private var spentQuota: UsageQuota {
        UsageQuota(percentRemaining: 20, quotaType: .session, providerId: "claude",
                   resetsAt: Date().addingTimeInterval(30 * 60), windowDuration: 5 * 3600)
    }

    /// The same window at 62% — a healthier login to compare against.
    private var comfortableQuota: UsageQuota {
        UsageQuota(percentRemaining: 62, quotaType: .session, providerId: "claude",
                   resetsAt: Date().addingTimeInterval(2 * 3600), windowDuration: 5 * 3600)
    }

    /// A balance with no ceiling — a quota with no share at all.
    private var openBalance: UsageQuota {
        UsageQuota(percentRemaining: 100, quotaType: .session, providerId: "claude", dollarRemaining: 42)
    }

    private func snapshot(_ quotas: UsageQuota..., capturedAt: Date = Date()) -> UsageSnapshot {
        UsageSnapshot(providerId: "claude", quotas: quotas, capturedAt: capturedAt)
    }

    /// The Monitor's reads, stubbed to answer only what the test gives them.
    /// A read without a stub answers the failing default — the reading may
    /// ask nothing the test has not granted.
    private func reads(
        lineup logins: [Account],
        status: QuotaStatus = .healthy,
        ownStatus: QuotaStatus? = nil,
        usage: (Account) -> UsageSnapshot? = { _ in nil },
        days: Days? = nil
    ) -> MockLocalAPIMonitorReads {
        let reads = MockLocalAPIMonitorReads()
        given(reads).lineup.willReturn(logins)
        given(reads).overallStatus.willReturn(status)
        given(reads).product(of: .any).willReturn(nil)
        given(reads).lineupName(of: .any).willReturn("Work")
        given(reads).status(of: .any).willReturn(ownStatus)
        given(reads).days(of: .any, in: .any).willReturn(days)
        for login in logins {
            given(reads).usage(of: .matching { $0.id == login.id }).willReturn(usage(login))
        }
        return reads
    }

    // MARK: - `/status`

    @Test func `should point the lowest at the login with the least share left across the lineup`() throws {
        let work = login(label: "Work")
        let home = login(accountId: "home", label: "Home")
        let reading = MonitorLocalAPIReading(reads: reads(
            lineup: [work, home], status: .warning,
            usage: { $0.id == "claude" ? snapshot(spentQuota) : snapshot(comfortableQuota) }
        ))

        let summary = reading.statusSummary()

        #expect(summary.status == "warning")
        #expect(summary.providers == 2)
        let lowest = try #require(summary.lowest)
        #expect(lowest.provider == "claude")
        #expect(lowest.login == "claude")
        #expect(lowest.name == "Work")
        #expect(lowest.quota == "Session")
        #expect(lowest.key == "session")
        #expect(lowest.percentLeft == 20)
        #expect(lowest.resetsAt != nil)
    }

    @Test func `should leave the lowest out when no quota has a share`() {
        let work = login()
        let reading = MonitorLocalAPIReading(reads: reads(lineup: [work], usage: { _ in snapshot(openBalance) }))

        let summary = reading.statusSummary()

        #expect(summary.status == "healthy")
        #expect(summary.summary == "healthy")
        #expect(summary.lowest == nil)
    }

    // MARK: - `/providers`

    @Test func `should group the lineup's logins under their product in the lineup's order`() throws {
        let work = login(label: "Work")
        let home = login(accountId: "home", label: "Home")
        let focus = login(provider: "codex", accountId: "focus", label: "Focus")
        let reading = MonitorLocalAPIReading(reads: reads(
            lineup: [work, home, focus],
            usage: { $0.id == "claude" ? snapshot(spentQuota) : snapshot(comfortableQuota) }
        ))

        let report = reading.providersReport()

        let ids = report.providers.map { $0.id }
        #expect(ids == ["claude", "codex"])
        let claude = try #require(report.providers.first { $0.id == "claude" })
        // No product stands behind the logins, so the id stands in for the name.
        #expect(claude.name == "claude")
        #expect(claude.logins.map { $0.id } == ["claude", "claude.home"])
        let row = try #require(claude.logins.first)
        #expect(row.name == "Work")
        #expect(row.status == "healthy")
        #expect(row.best == false)
        #expect(row.inUse == false)
        #expect(row.plan == nil)
        #expect(row.source == nil)
        #expect(row.updatedAt != nil)
        #expect(row.quotas.count == 1)
        #expect(row.quotas.first?.percentLeft == 20)
    }

    @Test func `should read the login's own status when the policy answers for it`() throws {
        let work = login()
        let reading = MonitorLocalAPIReading(reads: reads(
            lineup: [work], status: .warning, ownStatus: .critical,
            usage: { _ in snapshot(comfortableQuota) }
        ))

        let report = reading.providersReport()

        let row = try #require(report.providers.first?.logins.first)
        #expect(row.status == "critical")
        // The overall status is the lineup's worst — not this login's report.
        #expect(row.quotas.first?.percentLeft == 62)
    }

    // MARK: - `/forecast`

    @Test func `should forecast the quota that has a line and leave the one without out`() throws {
        let work = login()
        let timeless = UsageQuota(percentRemaining: 40, quotaType: .session, providerId: "claude")
        let reading = MonitorLocalAPIReading(reads: reads(
            lineup: [work], usage: { _ in snapshot(spentQuota, timeless) }
        ))

        let report = reading.forecastReport()

        #expect(report.forecasts.count == 1)
        let line = try #require(report.forecasts.first)
        #expect(line.state == "lastsUntilReset")
        #expect(line.provider == "claude")
        #expect(line.login == "claude")
        #expect(line.loginName == "Work")
        #expect(line.quota == "Session")
        #expect(line.key == "session")
    }

    // MARK: - `/usage/days`

    @Test func `should read each watching login's days when asked`() async throws {
        let work = login()
        let stat = DailyUsageStat(date: Date(), totalCost: 1.5, totalTokens: 900,
                                  workingTime: 1800, sessionCount: 2)
        let reading = MonitorLocalAPIReading(reads: reads(lineup: [work], days: Days([stat], knowsCost: true)))

        let report = await reading.usageDays(count: 7)

        #expect(report.days == 7)
        #expect(report.logins.count == 1)
        let series = try #require(report.logins.first)
        #expect(series.id == "claude")
        #expect(series.name == "Work")
        #expect(series.days.count == 1)
        let day = try #require(series.days.first)
        #expect(day.cost == 1.5)
        #expect(day.tokens == 900)
        #expect(day.workingMinutes == 30)
        #expect(day.sessions == 2)
    }

    @Test func `should give a login with no history no series`() async {
        let work = login()
        let reading = MonitorLocalAPIReading(reads: reads(lineup: [work], days: nil))

        let report = await reading.usageDays(count: 7)

        #expect(report.logins.isEmpty)
    }
}
