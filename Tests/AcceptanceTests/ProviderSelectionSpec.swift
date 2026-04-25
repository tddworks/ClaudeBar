import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

/// Feature: Provider Selection
///
/// Users switch between AI providers via pills in the menu bar.
/// The monitor coordinates selection, refresh, and state transitions.
///
/// Behaviors covered:
/// - #4: User clicks a provider pill → switches view and triggers refresh
/// - #5: Only enabled providers appear as pills
/// - #6: Disabling the currently selected provider → auto-switches to first enabled
/// - #7: Provider selection persists across app restarts
@Suite("Feature: Provider Selection")
struct ProviderSelectionSpec {

    private struct TestClock: Clock {
        func sleep(for duration: TimeInterval) async throws {}
    }

    // MARK: - #4: Switch to a different provider

    @Suite("Scenario: Switch to a different provider")
    struct SwitchProvider {
        private struct TestClock: Clock {
            func sleep(for duration: TimeInterval) async throws {}
        }

        private static func makeSettings() -> MockProviderSettingsRepository {
            let mock = MockProviderSettingsRepository()
            given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
            given(mock).isEnabled(forProvider: .any).willReturn(true)
            given(mock).setEnabled(.any, forProvider: .any).willReturn()
            return mock
        }

        @Test
        func `selecting Codex switches view and triggers refresh`() async {
            // Given — Claude and Codex are both enabled
            let settings = Self.makeSettings()

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
                quotas: [UsageQuota(percentRemaining: 40, quotaType: .session, providerId: "codex")],
                capturedAt: Date()
            ))

            let claude = ClaudeProvider(probe: claudeProbe, settingsRepository: settings)
            let codex = CodexProvider(probe: codexProbe, settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude, codex]),
                clock: TestClock()
            )

            #expect(monitor.selectedProviderId == "claude")

            // When — user clicks Codex pill
            monitor.selectProvider(id: "codex")
            await monitor.refresh(providerId: "codex")

            // Then — Codex is selected and its quota data is refreshed
            #expect(monitor.selectedProviderId == "codex")
            #expect(codex.snapshot != nil)
            #expect(codex.snapshot?.quotas.first?.percentRemaining == 40)
        }
    }

    // MARK: - #5: Only enabled providers appear as pills

    @Suite("Scenario: Only enabled providers appear as pills")
    struct EnabledProviders {
        private struct TestClock: Clock {
            func sleep(for duration: TimeInterval) async throws {}
        }

        private static func makeSettings() -> MockProviderSettingsRepository {
            let mock = MockProviderSettingsRepository()
            given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
            given(mock).isEnabled(forProvider: .any).willReturn(true)
            given(mock).setEnabled(.any, forProvider: .any).willReturn()
            return mock
        }

        @Test
        func `disabled providers are hidden from the pill list`() {
            // Given — Claude enabled, Codex disabled
            let settings = Self.makeSettings()
            let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
            let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
            codex.isEnabled = false

            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude, codex]),
                clock: TestClock()
            )

            // Then — only Claude appears
            #expect(monitor.enabledProviders.count == 1)
            #expect(monitor.enabledProviders.first?.id == "claude")
        }

        @Test
        func `all enabled providers appear in the pill list`() {
            // Given — both enabled
            let settings = Self.makeSettings()
            let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
            let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude, codex]),
                clock: TestClock()
            )

            // Then
            #expect(monitor.enabledProviders.count == 2)
        }
    }

    // MARK: - #6: Disabling the currently selected provider → auto-switches

    @Suite("Scenario: Disabling the currently selected provider")
    struct DisableSelectedProvider {
        private struct TestClock: Clock {
            func sleep(for duration: TimeInterval) async throws {}
        }

        private static func makeSettings() -> MockProviderSettingsRepository {
            let mock = MockProviderSettingsRepository()
            given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
            given(mock).isEnabled(forProvider: .any).willReturn(true)
            given(mock).setEnabled(.any, forProvider: .any).willReturn()
            return mock
        }

        @Test
        func `disabling Claude auto-switches selection to Codex`() {
            // Given — Claude is selected
            let settings = Self.makeSettings()
            let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
            let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude, codex]),
                clock: TestClock()
            )
            #expect(monitor.selectedProviderId == "claude")

            // When — user disables Claude
            monitor.setProviderEnabled("claude", enabled: false)

            // Then — auto-switches to Codex
            #expect(claude.isEnabled == false)
            #expect(monitor.selectedProviderId == "codex")
        }

        @Test
        func `Claude disabled at startup selects first enabled provider`() {
            // Given — Claude disabled before init
            let settings = Self.makeSettings()
            let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
            let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
            claude.isEnabled = false

            // When — monitor initializes
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude, codex]),
                clock: TestClock()
            )

            // Then — Codex is automatically selected
            #expect(monitor.selectedProviderId == "codex")
        }
    }

    // MARK: - #7: Selecting a disabled provider is rejected

    @Suite("Scenario: Selecting a disabled provider")
    struct SelectDisabledProvider {
        private struct TestClock: Clock {
            func sleep(for duration: TimeInterval) async throws {}
        }

        @Test
        func `selecting disabled Codex keeps Claude selected`() {
            // Given — Codex is disabled
            let settings = MockProviderSettingsRepository()
            given(settings).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
            given(settings).isEnabled(forProvider: .any).willReturn(true)
            given(settings).setEnabled(.any, forProvider: .any).willReturn()

            let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
            let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
            codex.isEnabled = false

            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude, codex]),
                clock: TestClock()
            )

            // When — user tries to select disabled Codex
            monitor.selectProvider(id: "codex")

            // Then — Claude remains selected
            #expect(monitor.selectedProviderId == "claude")
        }
    }
}
