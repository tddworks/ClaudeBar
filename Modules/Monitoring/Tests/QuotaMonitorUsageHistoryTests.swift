import Foundation
import Testing
import Mockable
import Quotas
import DataSources
import Providers
@testable import Monitoring

/// *TODAY'S USAGE* read with a page: today and the thirty days, and never the
/// year — the year is read only when a year section is shown
/// (docs/features/usage-history/insights/design.md).
@MainActor
@Suite
struct QuotaMonitorUsageHistoryTests {
    private let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    /// A login whose log holds usage today and a hundred days ago — inside the
    /// year, outside the thirty days.
    private func history() throws -> UsageHistory {
        let dir = home.appendingPathComponent(".acme")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let lines = [Date(), Date().addingTimeInterval(-100 * 86_400)].map { at in
            #"{"at":\#(at.timeIntervalSince1970),"tokens":1000,"cost":2}"#
        }
        try lines.joined(separator: "\n").write(to: dir.appendingPathComponent("log.jsonl"), atomically: true, encoding: .utf8)
        let definition = UsageLog.Definition(records: UsageLog.Records(
            files: "~/.acme/*.jsonl", at: "$.at", tokens: UsageLog.Tokens(total: "$.tokens"), cost: "$.cost"))
        return UsageHistory(log: DataSources.makeUsageLog(definition, environment: { _ in nil }, homeDirectory: home))
    }

    private func monitor(with history: UsageHistory) -> QuotaMonitor {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(UsageSnapshot(providerId: "acme", quotas: [], capturedAt: Date()))
        return QuotaMonitor(providers: kept([
            stubbedProduct("acme", probe: probe, settings: settings, usageHistory: history),
        ]), clock: SystemClock())
    }

    @Test
    func `should read today and the last thirty days but not the year when a page refreshes`() async throws {
        let history = try history()
        let monitor = monitor(with: history)
        defer { try? FileManager.default.removeItem(at: home) }

        await monitor.refresh(ProductTab.everyProduct(in: monitor.providers)[0])

        #expect(history.report != nil)
        #expect(history.lastThirtyDays != nil)
        #expect(history.lastYear == nil)
    }

    @Test
    func `should read today's usage but not the year when the All page reads every login`() async throws {
        let history = try history()
        let monitor = monitor(with: history)
        defer { try? FileManager.default.removeItem(at: home) }

        await monitor.readToday()

        #expect(history.report != nil)
        #expect(history.lastYear == nil)
    }

    @Test
    func `should hold the year once a year section asks for it`() async throws {
        let history = try history()
        let monitor = monitor(with: history)
        defer { try? FileManager.default.removeItem(at: home) }

        await monitor.readToday()
        await history.readYear()

        #expect(history.lastYear != nil)
    }
}
