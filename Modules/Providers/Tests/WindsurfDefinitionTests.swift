@testable import DataSources
import Foundation
import Mockable
import Providers
import Quotas
import Testing

/// Windsurf as data: the plan Windsurf caches in its own database, read
/// read-only and mapped by `windsurf-plan.js`.
@MainActor @Suite
struct WindsurfDefinitionTests {
    static let plan = #"{"planName":"Pro","startTimestamp":1771610750000,"endTimestamp":1774029950000,"usage":{"messages":50000,"usedMessages":35650,"remainingMessages":14350,"flowActions":150000,"usedFlowActions":0,"remainingFlowActions":150000},"quotaUsage":{"dailyRemainingPercent":9,"weeklyRemainingPercent":54,"dailyResetAtUnix":1774080000,"weeklyResetAtUnix":1774166400}}"#

    /// A home folder whose Windsurf database holds `plan` as its saved plan,
    /// stored as Windsurf stores it; no database at all when `plan` is nil.
    private func home(_ plan: String?) throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = home.appendingPathComponent("Library/Application Support/Windsurf/User/globalStorage")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let plan else { return home }
        let quoted = plan.replacingOccurrences(of: "'", with: "''")
        let insert = plan.isEmpty ? "" : "INSERT INTO ItemTable VALUES ('windsurf.settings.cachedPlanInfo', CAST('\(quoted)' AS BLOB));"
        try SQLiteFiles.make(at: folder.appendingPathComponent("state.vscdb"),
                             "CREATE TABLE ItemTable(key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB); \(insert)")
        return home
    }

    private func make(_ plan: String? = Self.plan, now: Date = Date(timeIntervalSince1970: 1773000000)) throws -> Provider {
        let definition = try ProviderFactory.builtIn("windsurf")
        let folder = try home(plan)
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
}
