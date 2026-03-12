import Testing
import Foundation
import Mockable
@testable import Domain

@Suite
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
}
