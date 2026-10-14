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
        func sleep(for duration: Duration) async throws {}
        func sleep(nanoseconds: UInt64) async throws {}
    }

    // MARK: - #4: Switch to a different provider

    @Suite("Scenario: Switch to a different provider")
    @MainActor
    struct SwitchProvider {
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

        @Test
        func `should select Codex and show its 40% left when the person picks the Codex pill and it refreshes`() async {
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

            let claudeProduct = stubbedProduct("claude", probe: claudeProbe, settings: settings)
            let claude = claudeProduct.defaultAccount
            let codexProduct = stubbedProduct("codex", probe: codexProbe, settings: settings)
            let codex = codexProduct.defaultAccount
            let monitor = QuotaMonitor(
                providers: kept([claudeProduct, codexProduct]),
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
    @MainActor
    struct EnabledProviders {
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

        @Test
        func `should show no pill for a turned-off provider`() {
            // Given — Claude enabled, Codex disabled
            let settings = Self.makeSettings()
            let claudeProduct = stubbedProduct("claude", probe: MockUsageProbe(), settings: settings)
            let claude = claudeProduct.defaultAccount
            let codexProduct = stubbedProduct("codex", probe: MockUsageProbe(), settings: settings)
            let codex = codexProduct.defaultAccount
            codex.isEnabled = false

            let monitor = QuotaMonitor(
                providers: kept([claudeProduct, codexProduct]),
                clock: TestClock()
            )

            // Then — only Claude appears
            #expect(monitor.lineup.count == 1)
            #expect(monitor.lineup.first?.id == "claude")
        }

        @Test
        func `should show a pill for every provider that is on`() {
            // Given — both enabled
            let settings = Self.makeSettings()
            let claudeProduct = stubbedProduct("claude", probe: MockUsageProbe(), settings: settings)
            let claude = claudeProduct.defaultAccount
            let codexProduct = stubbedProduct("codex", probe: MockUsageProbe(), settings: settings)
            let codex = codexProduct.defaultAccount
            let monitor = QuotaMonitor(
                providers: kept([claudeProduct, codexProduct]),
                clock: TestClock()
            )

            // Then
            #expect(monitor.lineup.count == 2)
        }
    }

    // MARK: - #6: Disabling the currently selected provider → auto-switches

    @Suite("Scenario: Disabling the currently selected provider")
    @MainActor
    struct DisableSelectedProvider {
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

        @Test
        func `should select Codex when the person turns off the selected Claude`() throws {
            // Given — Claude is selected
            let settings = Self.makeSettings()
            let claudeProduct = stubbedProduct("claude", probe: MockUsageProbe(), settings: settings)
            let codexProduct = stubbedProduct("codex", probe: MockUsageProbe(), settings: settings)
            let monitor = QuotaMonitor(
                providers: kept([claudeProduct, codexProduct]),
                clock: TestClock()
            )
            #expect(monitor.selectedProviderId == "claude")

            // When — the person turns the product off in Settings
            let claude = try #require(monitor.productTabs.first { $0.id == "claude" })
            monitor.setProductEnabled(claude, enabled: false)

            // Then — auto-switches to Codex
            #expect(monitor.selectedProviderId == "codex")
        }

        @Test
        func `should select the first provider that is on when the person turned Claude off`() {
            // Given — Claude turned off before init, so it has no page to open on
            let settings = Self.makeSettings()
            let claudeProduct = stubbedProduct("claude", probe: MockUsageProbe(), settings: settings)
            let codexProduct = stubbedProduct("codex", probe: MockUsageProbe(), settings: settings)
            claudeProduct.isEnabled = false

            // When — monitor initializes
            let monitor = QuotaMonitor(
                providers: kept([claudeProduct, codexProduct]),
                clock: TestClock()
            )

            // Then — Codex is automatically selected
            #expect(monitor.selectedProviderId == "codex")
        }
    }

    // MARK: - #7: Selecting a disabled provider is rejected

    @Suite("Scenario: Selecting a disabled provider")
    @MainActor
    struct SelectDisabledProvider {
        private struct TestClock: Clock {
            func sleep(for duration: Duration) async throws {}
            func sleep(nanoseconds: UInt64) async throws {}
        }

        @Test
        func `should keep Claude selected when the person tries to pick a turned-off Codex`() {
            // Given — Codex is disabled
            let settings = MockProviderSettingsRepository()
            given(settings).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
            given(settings).isEnabled(forProvider: .any).willReturn(true)
            given(settings).setEnabled(.any, forProvider: .any).willReturn()

            let claudeProduct = stubbedProduct("claude", probe: MockUsageProbe(), settings: settings)
            let claude = claudeProduct.defaultAccount
            let codexProduct = stubbedProduct("codex", probe: MockUsageProbe(), settings: settings)
            let codex = codexProduct.defaultAccount
            codex.isEnabled = false

            let monitor = QuotaMonitor(
                providers: kept([claudeProduct, codexProduct]),
                clock: TestClock()
            )

            // When — user tries to select disabled Codex
            monitor.selectProvider(id: "codex")

            // Then — Claude remains selected
            #expect(monitor.selectedProviderId == "claude")
        }
    }
}
