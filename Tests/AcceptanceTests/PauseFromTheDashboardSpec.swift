import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

/// Feature: Pause a login from the dashboard
///
/// Mia watches two logins of one product. She stops watching *work* for the
/// weekend from the popover: it leaves the menu bar, the chips and every
/// judgement, stays on the product's page under PAUSED with its last numbers,
/// and comes back with one *Resume*.
///
/// (docs/architecture/USER_JOURNEYS.md moment 2a,
///  docs/features/multi-account/design.md §3.5)
@Suite("Feature: Pause a login from the dashboard")
struct PauseFromTheDashboardSpec {
    private static func makeSettings() -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(mock).isEnabled(forProvider: .any).willReturn(true)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        return mock
    }

    private static func usage(_ left: Double, _ id: String) -> UsageSnapshot {
        UsageSnapshot(providerId: id,
                      quotas: [UsageQuota(percentRemaining: left, quotaType: .session, providerId: id)],
                      capturedAt: Date())
    }

    @Suite("Scenario: Pausing a login from the popover")
    @MainActor
    struct Pausing {
        private struct TestClock: Clock {
            func sleep(for duration: Duration) async throws {}
            func sleep(nanoseconds: UInt64) async throws {}
        }

        @Test
        func `should stop watching a paused login and keep it on the product's page`() async throws {
            // Given — Codex is on, its usage fetched
            let settings = PauseFromTheDashboardSpec.makeSettings()
            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willReturn(PauseFromTheDashboardSpec.usage(18, "codex"))
            let codexProduct = stubbedProduct("codex", probe: probe, settings: settings)
            let codex = codexProduct.defaultAccount
            let monitor = QuotaMonitor(providers: kept([codexProduct]), clock: TestClock())
            await monitor.refreshAll()
            #expect(monitor.lineup.map(\.id) == ["codex"])

            // When — she pauses the login the popover is showing
            monitor.pause(codex)

            // Then — nothing is watched, the page says PAUSED and keeps the last numbers
            #expect(monitor.lineup.isEmpty)
            #expect(monitor.selectedTab?.id == "codex")
            #expect(monitor.selectedTab?.paused.map(\.id) == ["codex"])
            #expect(monitor.selectedBadge == .paused)
            #expect(monitor.usage(of: codex)?.lowestQuota?.percentRemaining == 18)
        }

        @Test
        func `should watch a login again when she resumes it`() async throws {
            // Given — a paused login
            let settings = PauseFromTheDashboardSpec.makeSettings()
            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willReturn(PauseFromTheDashboardSpec.usage(18, "codex"))
            let codexProduct = stubbedProduct("codex", probe: probe, settings: settings)
            let codex = codexProduct.defaultAccount
            let monitor = QuotaMonitor(providers: kept([codexProduct]), clock: TestClock())
            monitor.pause(codex)

            // When — she presses Resume on Monday
            monitor.resume(codex)
            await monitor.refreshAll()

            // Then — it is watched again, with what it last showed
            #expect(monitor.lineup.map(\.id) == ["codex"])
            #expect(monitor.overallStatus == .critical)
            #expect(monitor.selectedBadge == .quota(.critical))
        }

        @Test
        func `should leave a paused login out of the All page and out of the menu bar`() async throws {
            // Given — two products, both with usage
            let settings = PauseFromTheDashboardSpec.makeSettings()
            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willReturn(PauseFromTheDashboardSpec.usage(18, "claude"))
            let claudeProduct = stubbedProduct("claude", probe: probe, settings: settings)
            let geminiProduct = stubbedProduct("gemini", probe: probe, settings: settings)
            let monitor = QuotaMonitor(providers: kept([claudeProduct, geminiProduct]), clock: TestClock())
            await monitor.refreshAll()
            #expect(Overview(monitor).cards.map(\.id) == ["claude", "gemini"])

            // When — she pauses Claude
            monitor.pause(claudeProduct.defaultAccount)

            // Then — All shows only Gemini, and the menu bar has no Claude entry
            #expect(Overview(monitor).cards.map(\.id) == ["gemini"])
            #expect(monitor.lineup.map(\.id) == ["gemini"])
        }
    }
}
