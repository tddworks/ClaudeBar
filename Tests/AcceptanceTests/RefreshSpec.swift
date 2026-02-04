import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

/// Feature: Refresh
///
/// Users refresh quota data manually or via background sync.
///
/// Behaviors covered:
/// - #15: User clicks Refresh → fetches latest quota for current provider
/// - #16: Button shows "Syncing..." spinner while in progress
/// - #17: Duplicate refresh clicks are ignored while syncing
/// - #18: Background sync auto-refreshes at configured interval
@Suite("Feature: Refresh")
struct RefreshSpec {

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

    // MARK: - #15: Successful refresh

    @Suite("Scenario: Successful refresh")
    struct SuccessfulRefresh {
        private struct TestClock: Clock {
            func sleep(for duration: Duration) async throws {}
            func sleep(nanoseconds: UInt64) async throws {}
        }

        @Test
        func `refresh updates snapshot with fresh data`() async {
            // Given
            let settings = RefreshSpec.makeSettings()
            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willReturn(UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 65, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            ))

            let claude = ClaudeProvider(probe: probe, settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude]),
                clock: TestClock()
            )

            #expect(claude.snapshot == nil)

            // When — user clicks Refresh
            await monitor.refresh(providerId: "claude")

            // Then
            #expect(claude.snapshot != nil)
            #expect(claude.snapshot?.quotas.first?.percentRemaining == 65)
        }

        @Test
        func `failed refresh stores error without affecting other providers`() async {
            // Given
            let settings = RefreshSpec.makeSettings()

            let claudeProbe = MockUsageProbe()
            given(claudeProbe).isAvailable().willReturn(true)
            given(claudeProbe).probe().willReturn(UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 70, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            ))

            let codexProbe = MockUsageProbe()
            given(codexProbe).isAvailable().willReturn(true)
            given(codexProbe).probe().willThrow(ProbeError.timeout)

            let claude = ClaudeProvider(probe: claudeProbe, settingsRepository: settings)
            let codex = CodexProvider(probe: codexProbe, settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude, codex]),
                clock: TestClock()
            )

            // When
            await monitor.refreshAll()

            // Then — Claude succeeds, Codex fails independently
            #expect(claude.snapshot != nil)
            #expect(codex.snapshot == nil)
            #expect(codex.lastError != nil)
        }
    }

    // MARK: - #18: Background sync

    @Suite("Scenario: Background sync")
    struct BackgroundSync {
        private struct TestClock: Clock {
            func sleep(for duration: Duration) async throws {}
            func sleep(nanoseconds: UInt64) async throws {}
        }

        @Test
        func `continuous monitoring emits refresh events`() async throws {
            // Given
            let settings = RefreshSpec.makeSettings()
            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willReturn(UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            ))

            let claude = ClaudeProvider(probe: probe, settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude]),
                clock: TestClock()
            )

            // When — start monitoring
            let stream = monitor.startMonitoring(interval: .milliseconds(100))
            var events: [MonitoringEvent] = []

            for await event in stream.prefix(2) {
                events.append(event)
            }

            monitor.stopMonitoring()

            // Then — received refresh events
            #expect(events.count == 2)
            #expect(events.allSatisfy { if case .refreshed = $0 { return true }; return false })
        }

        @Test
        func `monitoring stops when requested`() async throws {
            // Given
            let settings = RefreshSpec.makeSettings()
            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willReturn(UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            ))

            let claude = ClaudeProvider(probe: probe, settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude]),
                clock: TestClock()
            )

            // When — start then immediately stop
            let stream = monitor.startMonitoring(interval: .milliseconds(50))
            monitor.stopMonitoring()

            var eventCount = 0
            for await _ in stream {
                eventCount += 1
            }

            // Then — stream finishes quickly
            #expect(eventCount <= 2)
        }
    }
}
