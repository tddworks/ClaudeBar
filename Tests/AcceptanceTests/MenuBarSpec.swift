import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

/// Feature: Menu Bar
///
/// The menu bar icon reflects the overall quota status across
/// all enabled providers.
///
/// Behaviors covered:
/// - #1: User clicks menu bar icon → sees popup
/// - #2: Menu bar icon reflects worst quota status across providers
/// - #3: Menu bar icon appearance changes with theme
@Suite("Feature: Menu Bar")
struct MenuBarSpec {

    private struct TestClock: Clock {
        func sleep(for duration: Duration) async throws {}
        func sleep(nanoseconds: UInt64) async throws {}
    }

    private static func makeSettings() -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(mock).isEnabled(forProvider: .any).willReturn(true)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        return mock
    }

    // MARK: - #2: Overall status reflects worst provider

    @Suite("Scenario: Overall status calculation")
    struct OverallStatus {
        private struct TestClock: Clock {
            func sleep(for duration: Duration) async throws {}
            func sleep(nanoseconds: UInt64) async throws {}
        }

        @Test
        func `worst status across providers wins`() async {
            // Given — Claude healthy (70%), Codex critical (15%)
            let settings = MenuBarSpec.makeSettings()

            let claudeProbe = MockUsageProbe()
            given(claudeProbe).isAvailable().willReturn(true)
            given(claudeProbe).probe().willReturn(UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 70, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            ))

            let codexProbe = MockUsageProbe()
            given(codexProbe).isAvailable().willReturn(true)
            given(codexProbe).probe().willReturn(UsageSnapshot(
                providerId: "codex",
                quotas: [UsageQuota(percentRemaining: 15, quotaType: .session, providerId: "codex")],
                capturedAt: Date()
            ))

            let claude = ClaudeProvider(probe: claudeProbe, settingsRepository: settings)
            let codex = CodexProvider(probe: codexProbe, settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude, codex]),
                clock: TestClock()
            )

            // When
            await monitor.refreshAll()

            // Then — critical (worst) wins
            #expect(monitor.overallStatus == .critical)
        }

        @Test
        func `disabled provider does not affect overall status`() async {
            // Given — Claude healthy, Codex critical but disabled
            let settings = MenuBarSpec.makeSettings()

            let claudeProbe = MockUsageProbe()
            given(claudeProbe).isAvailable().willReturn(true)
            given(claudeProbe).probe().willReturn(UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 70, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            ))

            let codexProbe = MockUsageProbe()
            given(codexProbe).isAvailable().willReturn(true)
            given(codexProbe).probe().willReturn(UsageSnapshot(
                providerId: "codex",
                quotas: [UsageQuota(percentRemaining: 5, quotaType: .session, providerId: "codex")],
                capturedAt: Date()
            ))

            let claude = ClaudeProvider(probe: claudeProbe, settingsRepository: settings)
            let codex = CodexProvider(probe: codexProbe, settingsRepository: settings)
            codex.isEnabled = false

            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude, codex]),
                clock: TestClock()
            )

            await monitor.refreshAll()

            // Then — only enabled provider counts
            #expect(monitor.overallStatus == .healthy)
        }

        @Test
        func `selected provider status shown in menu bar`() async {
            // Given
            let settings = MenuBarSpec.makeSettings()

            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willReturn(UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 30, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            ))

            let claude = ClaudeProvider(probe: probe, settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude]),
                clock: TestClock()
            )

            // When
            await monitor.refresh(providerId: "claude")

            // Then — selected provider status reflects quota
            #expect(monitor.selectedProviderStatus == .warning)
        }

        @Test
        func `no snapshots defaults to healthy`() {
            // Given — fresh monitor, no refresh yet
            let settings = MenuBarSpec.makeSettings()
            let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude]),
                clock: TestClock()
            )

            // Then
            #expect(monitor.overallStatus == .healthy)
            #expect(monitor.selectedProviderStatus == .healthy)
        }
    }
}
