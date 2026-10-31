@testable import DataSources
import Foundation
import Mockable
import Providers
import Quotas
import Testing

/// Windsurf as data: the plan Windsurf, now Devin Desktop, caches in its own
/// database, read read-only and mapped by `windsurf-plan.js`.
@MainActor @Suite
struct WindsurfDefinitionTests {
    static let plan = #"{"planName":"Pro","startTimestamp":1771610750000,"endTimestamp":1774029950000,"usage":{"messages":50000,"usedMessages":35650,"remainingMessages":14350,"flowActions":150000,"usedFlowActions":0,"remainingFlowActions":150000},"quotaUsage":{"dailyRemainingPercent":9,"weeklyRemainingPercent":54,"dailyResetAtUnix":1774080000,"weeklyResetAtUnix":1774166400}}"#

    /// A home folder whose Windsurf database holds `plan` as its saved plan,
    /// stored as Windsurf stores it; no database at all when `plan` is nil.
    private func home(_ plan: String?) throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Library/Application Support/Windsurf/User/globalStorage"),
                                                withIntermediateDirectories: true)
        if let plan { try save(plan, app: "Windsurf", in: home) }
        return home
    }

    /// `plan` saved by the app whose data folder is `app`, the database last
    /// changed at `changed` when given.
    private func save(_ plan: String, app: String, in home: URL, changed: Date? = nil) throws {
        try save(plan.isEmpty ? [] : [("windsurf.settings.cachedPlanInfo", plan)], app: app, in: home, changed: changed)
    }

    /// `rows` (key, value) saved by the app whose data folder is `app`.
    private func save(_ rows: [(String, String)], app: String, in home: URL, changed: Date? = nil) throws {
        let folder = home.appendingPathComponent("Library/Application Support/\(app)/User/globalStorage")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let inserts = rows.map { key, value in
            "INSERT INTO ItemTable VALUES ('\(key)', CAST('\(value.replacingOccurrences(of: "'", with: "''"))' AS BLOB));"
        }.joined(separator: " ")
        let database = folder.appendingPathComponent("state.vscdb")
        try SQLiteFiles.make(at: database, "CREATE TABLE ItemTable(key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB); \(inserts)")
        if let changed { try FileManager.default.setAttributes([.modificationDate: changed], ofItemAtPath: database.path) }
    }

    private func make(_ plan: String? = Self.plan, now: Date = Date(timeIntervalSince1970: 1773000000)) throws -> Provider {
        try make(home: try home(plan), now: now)
    }

    private func make(home folder: URL, now: Date = Date(timeIntervalSince1970: 1773000000)) throws -> Provider {
        let definition = try ProviderFactory.builtIn("windsurf")
        var platform = Platform.current
        platform.applicationData = { home, _ in home.appendingPathComponent("Library/Application Support") }
        let fixturePlatform = platform
        return Provider(definition: definition, settings: InMemoryProviderSettings(), makeDataSource: { source, _ in
            DataSources.make(source, providerId: definition.id, platform: fixturePlatform, network: MockNetworkClient(),
                             scripts: ProviderFactory.builtInScripts, environment: { _ in nil },
                             homeDirectory: folder, now: { now })
        })
    }

    @Test
    func `should be Windsurf, off until turned on, with its dashboard and icon`() throws {
        let windsurf = try make()
        #expect(windsurf.id == "windsurf")
        #expect(windsurf.name == "Windsurf")
        #expect(windsurf.plainIsInLineup == false)
        #expect(windsurf.definition.profile.links.dashboard == URL(string: "https://windsurf.com/subscription/usage"))
        #expect(windsurf.definition.profile.look.icon == "WindsurfIcon")
    }

    @Test
    func `should read Windsurf's own database, without running anything`() throws {
        let windsurf = try make()
        let source = try #require(windsurf.definition.dataSources.first)
        #expect(source.fetch.connection.commands.isEmpty)
        #expect(source.fetch.connection.urls.isEmpty)
    }

    @Test
    func `should show the daily and weekly quota left, the reset times and the plan`() async throws {
        let usage = try await make().refreshPlain()
        let daily = try #require(usage.quotas.first { $0.quotaType == .timeLimit("Daily") })
        #expect(daily.percentRemaining == 9)
        #expect(daily.resetsAt == Date(timeIntervalSince1970: 1774080000))
        let weekly = try #require(usage.quota(for: .weekly))
        #expect(weekly.percentRemaining == 54)
        #expect(weekly.resetsAt == Date(timeIntervalSince1970: 1774166400))
        #expect(usage.accountTier == .custom("Pro"))
    }

    @Test
    func `should show messages and flow actions when the plan has no daily or weekly quota`() async throws {
        let output = #"{"planName":"Teams","endTimestamp":1774029950000,"usage":{"messages":50000,"usedMessages":35650,"flowActions":150000,"remainingFlowActions":120000}}"#
        let usage = try await make(output).refreshPlain()
        let messages = try #require(usage.quotas.first { $0.quotaType == .modelSpecific("Messages") })
        #expect(abs(messages.percentRemaining - 28.7) < 0.0001)
        #expect(messages.resetText == "35650/50000 used")
        #expect(messages.resetsAt == Date(timeIntervalSince1970: 1774029950))
        let flow = try #require(usage.quotas.first { $0.quotaType == .modelSpecific("Flow actions") })
        #expect(flow.percentRemaining == 80)
    }

    @Test
    func `should say the saved plan is out of date when its period has ended, instead of showing old numbers`() async throws {
        let output = #"{"planName":"Pro","endTimestamp":1749360995879,"usage":{"messages":2500,"usedMessages":0}}"#
        let windsurf = try make(output, now: Date(timeIntervalSince1970: 1760000000))
        let account = windsurf.defaultAccount
        await #expect(throws: UsageError.executionFailed("Windsurf's saved plan is out of date. Open Windsurf to update it.")) {
            try await windsurf.refresh(account)
        }
        #expect(account.lastFailedStep == .mapping)
    }

    @Test
    func `should report no data on a free plan with nothing to measure`() async throws {
        let windsurf = try make(#"{"planName":"Free"}"#)
        await #expect(throws: UsageError.noData) { try await windsurf.refresh(windsurf.defaultAccount) }
    }

    @Test
    func `should ask to open Windsurf when it has saved no plan`() async throws {
        let windsurf = try make("")
        await #expect(throws: UsageError.sessionExpired(hint: "Open Windsurf and sign in, so it saves your plan on this Mac.")) {
            try await windsurf.refresh(windsurf.defaultAccount)
        }
    }

    @Test
    func `should not be set up when Windsurf has never run on this Mac`() async throws {
        let windsurf = try make(nil)
        #expect(await windsurf.isAvailable(windsurf.defaultAccount) == false)
    }

    @Test
    func `should read the plan Devin Desktop saves, now that Windsurf has become Devin Desktop`() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try save(Self.plan, app: "Devin", in: home)
        let windsurf = try make(home: home)
        #expect(await windsurf.isAvailable(windsurf.defaultAccount))
        let usage = try await windsurf.refreshPlain()
        #expect(usage.quota(for: .weekly)?.percentRemaining == 54)
    }

    @Test
    func `should read Devin Desktop's plan, not the older copy Windsurf left behind`() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let left = Self.plan.replacingOccurrences(of: #""weeklyRemainingPercent":54"#, with: #""weeklyRemainingPercent":10"#)
        try save(left, app: "Windsurf", in: home, changed: Date(timeIntervalSince1970: 1772000000))
        try save(Self.plan, app: "Devin", in: home)
        let usage = try await make(home: home).refreshPlain()
        #expect(usage.quota(for: .weekly)?.percentRemaining == 54)
    }

    // MARK: - Devin Desktop's own key

    /// Devin Desktop saves the plan under `windsurf.reactSettings.cachedPlanInfoData:<user id>`,
    /// with the quota at the top level. Shapes from Pulse's fixtures
    /// (qunqin24/Pulse `Tests/PulseTests/Fixtures/devin-*.json`, Apache-2.0),
    /// captured from Devin.app 3.10.23 on 2026-09-14; the user id is made up.
    static let devinKey = "windsurf.reactSettings.cachedPlanInfoData:user-0123456789abcdef0123456789abcdef"
    static let devinNow = Date(timeIntervalSince1970: 1789300000)
    static let devinPro = #"{"planName":"Pro","billingStrategy":"quota","duration":29,"startTimestamp":1789296110000,"endTimestamp":1791888110000,"remainingMessages":-1,"totalMessages":-1,"remainingFlexCredits":0,"dailyRemainingPercent":98,"weeklyRemainingPercent":99,"overageBalanceMicros":10000000,"dailyResetAtUnix":1789372800,"weeklyResetAtUnix":1789891200,"hideDailyQuota":false,"hideWeeklyQuota":false,"isFreeOrTrial":false,"isDevinFree":false}"#
    static let devinFree = #"{"planName":"Free","billingStrategy":"quota","duration":0,"startTimestamp":0,"endTimestamp":0,"remainingMessages":1750,"totalMessages":2500,"remainingFlexCredits":0,"dailyRemainingPercent":100,"weeklyRemainingPercent":100,"overageBalanceMicros":0,"dailyResetAtUnix":1789372800,"weeklyResetAtUnix":1789891200,"hideDailyQuota":false,"hideWeeklyQuota":false,"isFreeOrTrial":true,"isDevinFree":true}"#
    static let devinHiddenDaily = #"{"planName":"Team","billingStrategy":"quota","remainingMessages":-1,"totalMessages":-1,"dailyRemainingPercent":100,"weeklyRemainingPercent":42,"overageBalanceMicros":2500000,"dailyResetAtUnix":1789372800,"weeklyResetAtUnix":1789891200,"hideDailyQuota":true,"hideWeeklyQuota":false}"#

    private func devin(_ rows: [(String, String)]) async throws -> UsageSnapshot {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try save(rows, app: "Devin", in: home)
        return try await make(home: home, now: Self.devinNow).refreshPlain()
    }

    @Test
    func `should read the plan Devin Desktop saves under its own key`() async throws {
        let usage = try await devin([(Self.devinKey, Self.devinPro)])
        let daily = try #require(usage.quotas.first { $0.quotaType == .timeLimit("Daily") })
        #expect(daily.percentRemaining == 98)
        #expect(daily.resetsAt == Date(timeIntervalSince1970: 1789372800))
        let weekly = try #require(usage.quota(for: .weekly))
        #expect(weekly.percentRemaining == 99)
        #expect(weekly.resetsAt == Date(timeIntervalSince1970: 1789891200))
        #expect(usage.accountTier == .custom("Pro"))
        #expect(!usage.quotas.contains { $0.quotaType == .modelSpecific("Messages") })
    }

    @Test
    func `should read Devin Desktop's own key before the key Windsurf used`() async throws {
        let usage = try await devin([("windsurf.settings.cachedPlanInfo", Self.plan), (Self.devinKey, Self.devinPro)])
        #expect(usage.quota(for: .weekly)?.percentRemaining == 99)
    }

    @Test
    func `should show a free plan's message pool, which has no period, beside its daily and weekly quota`() async throws {
        let usage = try await devin([(Self.devinKey, Self.devinFree)])
        let messages = try #require(usage.quotas.first { $0.quotaType == .modelSpecific("Messages") })
        #expect(messages.percentRemaining == 70)
        #expect(messages.resetText == "750/2500 used")
        #expect(messages.resetsAt == nil)
        #expect(usage.quota(for: .weekly)?.percentRemaining == 100)
        #expect(usage.accountTier == .custom("Free"))
    }

    @Test
    func `should leave out a quota Devin Desktop hides`() async throws {
        let usage = try await devin([(Self.devinKey, Self.devinHiddenDaily)])
        #expect(!usage.quotas.contains { $0.quotaType == .timeLimit("Daily") })
        #expect(usage.quota(for: .weekly)?.percentRemaining == 42)
    }

    @Test
    func `should read the account whose plan runs longest when two signed in on this computer`() async throws {
        let ended = Self.devinPro.replacingOccurrences(of: #""weeklyRemainingPercent":99"#, with: #""weeklyRemainingPercent":5"#)
            .replacingOccurrences(of: "1791888110000", with: "1789299000000")
        let usage = try await devin([("windsurf.reactSettings.cachedPlanInfoData:user-ffffffffffffffffffffffffffffffff", ended),
                                     (Self.devinKey, Self.devinPro)])
        #expect(usage.quota(for: .weekly)?.percentRemaining == 99)
    }
}
