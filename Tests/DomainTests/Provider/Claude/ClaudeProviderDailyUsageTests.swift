import Testing
import Foundation
import Mockable
@testable import Domain

@Suite
@MainActor
struct ClaudeProviderDailyUsageTests {

    private func makeSettingsRepository() -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(mock).isEnabled(forProvider: .any).willReturn(true)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        return mock
    }

    private func makeSnapshot() -> UsageSnapshot {
        UsageSnapshot(
            providerId: "claude",
            quotas: [UsageQuota(percentRemaining: 62, quotaType: .weekly, providerId: "claude")],
            capturedAt: Date()
        )
    }

    @Test
    func `refresh attaches daily report when today has usage`() async throws {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(makeSnapshot())

        let mockAnalyzer = MockDailyUsageAnalyzing()
        let report = DailyUsageReport(
            today: DailyUsageStat(date: Date(), totalCost: 14.26, totalTokens: 19_498_439, workingTime: 3600, sessionCount: 3),
            previous: DailyUsageStat(date: Date().addingTimeInterval(-86400), totalCost: 41.73, totalTokens: 59_706_443, workingTime: 7200, sessionCount: 5)
        )
        given(mockAnalyzer).analyzeToday().willReturn(report)

        let claude = ClaudeProvider(probe: mockProbe, settingsRepository: settings, dailyUsageAnalyzer: mockAnalyzer)
        let snapshot = try await claude.refresh()

        #expect(snapshot.dailyUsageReport != nil)
        #expect(snapshot.dailyUsageReport?.today.totalCost == 14.26)
        #expect(snapshot.dailyUsageReport?.previous.totalCost == 41.73)
    }

    @Test
    func `refresh attaches daily report when only previous day has usage`() async throws {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(makeSnapshot())

        let mockAnalyzer = MockDailyUsageAnalyzing()
        let report = DailyUsageReport(
            today: DailyUsageStat.empty(for: Date()),
            previous: DailyUsageStat(date: Date().addingTimeInterval(-86400), totalCost: 394.92, totalTokens: 195_900_000, workingTime: 28800, sessionCount: 10)
        )
        given(mockAnalyzer).analyzeToday().willReturn(report)

        let claude = ClaudeProvider(probe: mockProbe, settingsRepository: settings, dailyUsageAnalyzer: mockAnalyzer)
        let snapshot = try await claude.refresh()

        #expect(snapshot.dailyUsageReport != nil)
        #expect(snapshot.dailyUsageReport?.today.isEmpty == true)
        #expect(snapshot.dailyUsageReport?.previous.totalCost == 394.92)
    }

    @Test
    func `refresh does not attach daily report when both days are empty`() async throws {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(makeSnapshot())

        let mockAnalyzer = MockDailyUsageAnalyzing()
        let report = DailyUsageReport(
            today: DailyUsageStat.empty(for: Date()),
            previous: DailyUsageStat.empty(for: Date().addingTimeInterval(-86400))
        )
        given(mockAnalyzer).analyzeToday().willReturn(report)

        let claude = ClaudeProvider(probe: mockProbe, settingsRepository: settings, dailyUsageAnalyzer: mockAnalyzer)
        let snapshot = try await claude.refresh()

        #expect(snapshot.dailyUsageReport == nil)
    }

    @Test
    func `refresh does not attach daily report when analyzer is nil`() async throws {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(makeSnapshot())

        let claude = ClaudeProvider(probe: mockProbe, settingsRepository: settings)
        let snapshot = try await claude.refresh()

        #expect(snapshot.dailyUsageReport == nil)
    }

    // MARK: - Background refresh skips the daily scan (issue #204)

    /// A daily-usage analyzer that records how many times it ran, so a test can
    /// assert the expensive JSONL scan was *skipped* (state), not just that its
    /// result wasn't attached.
    private final class CountingDailyUsageAnalyzer: DailyUsageAnalyzing, @unchecked Sendable {
        private let lock = NSLock()
        private var _calls = 0
        private let report: DailyUsageReport

        init(report: DailyUsageReport) { self.report = report }

        var calls: Int { lock.withLock { _calls } }

        func analyzeToday() async throws -> DailyUsageReport {
            lock.withLock { _calls += 1 }
            return report
        }
    }

    private func makeTodayReport() -> DailyUsageReport {
        DailyUsageReport(
            today: DailyUsageStat(date: Date(), totalCost: 14.26, totalTokens: 19_498_439, workingTime: 3600, sessionCount: 3),
            previous: DailyUsageStat.empty(for: Date().addingTimeInterval(-86400))
        )
    }

    @Test
    func `background refresh skips the daily usage scan entirely`() async throws {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(makeSnapshot())
        let analyzer = CountingDailyUsageAnalyzer(report: makeTodayReport())

        let claude = ClaudeProvider(probe: mockProbe, settingsRepository: settings, dailyUsageAnalyzer: analyzer)
        let snapshot = try await claude.refresh(.background)

        // The menu-bar label never shows the daily report, so the background poll
        // must avoid the JSONL scan altogether — the power win in #204.
        #expect(analyzer.calls == 0)
        #expect(snapshot.dailyUsageReport == nil)
    }

    @Test
    func `interactive refresh runs the daily usage scan and attaches the report`() async throws {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(makeSnapshot())
        let analyzer = CountingDailyUsageAnalyzer(report: makeTodayReport())

        let claude = ClaudeProvider(probe: mockProbe, settingsRepository: settings, dailyUsageAnalyzer: analyzer)
        let snapshot = try await claude.refresh(.interactive)

        #expect(analyzer.calls == 1)
        #expect(snapshot.dailyUsageReport != nil)
    }
}
