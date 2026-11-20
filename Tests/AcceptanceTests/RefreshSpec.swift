import Quotas
import Providers
import Monitoring
import Testing
import Foundation
import Mockable

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
    @MainActor
    struct SuccessfulRefresh {
        private struct TestClock: Clock {
            func sleep(for duration: Duration) async throws {}
            func sleep(nanoseconds: UInt64) async throws {}
        }

        @Test
        func `should show Claude's latest quotas after the person clicks Refresh`() async {
            // Given
            let settings = RefreshSpec.makeSettings()
            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willReturn(UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 65, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            ))

            let claudeProduct = stubbedProduct("claude", probe: probe, settings: settings)
            let claude = claudeProduct.defaultAccount
            let monitor = QuotaMonitor(
                providers: kept([claudeProduct]),
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
        func `should show Codex's error and still show Claude's quotas when only Codex times out`() async {
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
            given(codexProbe).probe().willThrow(UsageError.timeout)

            let claudeProduct = stubbedProduct("claude", probe: claudeProbe, settings: settings)
            let claude = claudeProduct.defaultAccount
            let codexProduct = stubbedProduct("codex", probe: codexProbe, settings: settings)
            let codex = codexProduct.defaultAccount
            let monitor = QuotaMonitor(
                providers: kept([claudeProduct, codexProduct]),
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
    @MainActor
    struct BackgroundSync {
        private struct TestClock: Clock {
            func sleep(for duration: Duration) async throws {}
            func sleep(nanoseconds: UInt64) async throws {}
        }

        @Test
        func `should keep refreshing in the background while monitoring runs`() async throws {
            // Given
            let settings = RefreshSpec.makeSettings()
            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willReturn(UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            ))

            let claudeProduct = stubbedProduct("claude", probe: probe, settings: settings)
            let claude = claudeProduct.defaultAccount
            let monitor = QuotaMonitor(
                providers: kept([claudeProduct]),
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
        func `should stop refreshing in the background once monitoring is stopped`() async throws {
            // Given
            let settings = RefreshSpec.makeSettings()
            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willReturn(UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            ))

            let claudeProduct = stubbedProduct("claude", probe: probe, settings: settings)
            let claude = claudeProduct.defaultAccount
            let monitor = QuotaMonitor(
                providers: kept([claudeProduct]),
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

        // MARK: - #204: Power-conscious background refresh

        /// A clock that records each requested sleep, then ends the loop by
        /// throwing — so one deterministic tick reveals the background cadence.
        private final class RecordingClock: Clock, @unchecked Sendable {
            private let lock = NSLock()
            private var _durations: [Duration] = []
            var durations: [Duration] { lock.withLock { _durations } }
            func sleep(for duration: Duration) async throws {
                lock.withLock { _durations.append(duration) }
                throw CancellationError()
            }
            func sleep(nanoseconds: UInt64) async throws {
                try await sleep(for: .nanoseconds(Int64(nanoseconds)))
            }
        }

        /// Minimal settings fixing Claude's data source, so a scenario can
        /// exercise API-mode background behavior end-to-end.
        private final class ClaudeModeSettings: ProviderSettingsRepository, @unchecked Sendable {
            let mode: String
            init(mode: String) { self.mode = mode }
            func isEnabled(forProvider id: String) -> Bool { true }
            func isEnabled(forProvider id: String, defaultValue: Bool) -> Bool { true }
            func setEnabled(_ enabled: Bool, forProvider id: String) {}
            func customCardURL(forProvider id: String) -> String? { nil }
            func setCustomCardURL(_ url: String?, forProvider id: String) {}
            func hiddenQuotaKeys(forProvider id: String) -> Set<String> { [] }
            func setHiddenQuotaKeys(_ keys: Set<String>, forProvider id: String) {}
            func dataSourceKind(forProvider id: String) -> String? { mode }
        }

        /// A probe that returns the next snapshot in a sequence on each call, so a
        /// test can tell successive refreshes apart by their data.
        private final class SequentialProbe: UsageProbe, @unchecked Sendable {
            private let lock = NSLock()
            private var index = 0
            private let snapshots: [UsageSnapshot]
            init(_ snapshots: [UsageSnapshot]) { self.snapshots = snapshots }
            func probe() async throws -> UsageSnapshot {
                lock.withLock {
                    let snapshot = snapshots[min(index, snapshots.count - 1)]
                    index += 1
                    return snapshot
                }
            }
            func isAvailable() async -> Bool { true }
        }

        @Test
        func `should keep showing the CLI's quotas when Claude refreshes in the background in CLI mode`() async {
            // Given — a CLI-mode Claude provider (base settings → CLI).
            let settings = RefreshSpec.makeSettings()
            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willReturn(UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 42, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            ))
            let claudeProduct = stubbedProduct("claude", probe: probe, settings: settings)
            let claude = claudeProduct.defaultAccount
            let monitor = QuotaMonitor(
                providers: kept([claudeProduct]),
                clock: TestClock()
            )

            // When — background sync runs a cycle.
            let stream = monitor.startMonitoring(interval: .seconds(600))
            for await _ in stream.prefix(1) {}
            monitor.stopMonitoring()

            // Then — it refreshed via the CLI probe (no silent CLI→API swap).
            #expect(claude.snapshot?.quotas.first?.percentRemaining == 42)
        }

        @Test
        func `should refresh Claude in the background no more than every 15 minutes in API mode, even when the person picked 1 minute (#204)`() async {
            // Given — API-mode Claude and a user who picked the 1-minute option.
            let settings = ClaudeModeSettings(mode: "api")
            let snapshot = UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            )
            let cliProbe = MockUsageProbe()
            given(cliProbe).isAvailable().willReturn(true)
            given(cliProbe).probe().willReturn(snapshot)
            let apiProbe = MockUsageProbe()
            given(apiProbe).isAvailable().willReturn(true)
            given(apiProbe).probe().willReturn(snapshot)
            _ = cliProbe
            let claudeProduct = stubbedProduct("claude", probe: apiProbe, settings: settings, backgroundRefreshFloor: .seconds(900))
            let claude = claudeProduct.defaultAccount
            let clock = RecordingClock()
            let monitor = QuotaMonitor(providers: kept([claudeProduct]), clock: clock)

            // When — background sync runs one tick.
            let stream = monitor.startMonitoring(interval: .seconds(60), providerIds: ["claude"])
            for await _ in stream {}

            // Then — the cadence is floored to the 15-minute API cache TTL (#204).
            #expect(clock.durations == [.seconds(900)])
        }

        @Test
        func `should show fresh quotas on every Refresh click in API mode, despite the 15-minute background floor (#204)`() async {
            // Given — an API-mode Claude provider (which imposes a 15-min background
            // floor) returning a different snapshot on each probe.
            let settings = ClaudeModeSettings(mode: "api")
            let probe = SequentialProbe([
                UsageSnapshot(
                    providerId: "claude",
                    quotas: [UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "claude")],
                    capturedAt: Date()
                ),
                UsageSnapshot(
                    providerId: "claude",
                    quotas: [UsageQuota(percentRemaining: 60, quotaType: .session, providerId: "claude")],
                    capturedAt: Date()
                ),
            ])
            // No cache here: Claude's API keeps its usage 15 min, and that is
            // the data source's own law (ClaudeAPITests), not the Monitor's.
            let claudeProduct = stubbedProduct("claude", probe: probe, settings: settings)
            let claude = claudeProduct.defaultAccount
            let monitor = QuotaMonitor(providers: kept([claudeProduct]), clock: TestClock())

            // When/Then — two back-to-back user-initiated refreshes both update the
            // snapshot. The Monitor's floor governs only the background loop, never
            // the interactive path (#204), so neither call is gated.
            await monitor.refresh(providerId: "claude")
            #expect(claude.snapshot?.quotas.first?.percentRemaining == 80)
            await monitor.refresh(providerId: "claude")
            #expect(claude.snapshot?.quotas.first?.percentRemaining == 60)
        }
    }
}
