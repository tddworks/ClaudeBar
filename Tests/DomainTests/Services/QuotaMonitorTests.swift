import Testing
import Foundation
@testable import Domain
import Mockable

@Suite("Quota Monitor Tests")
struct QuotaMonitorTests {

    // MARK: - Single Provider Monitoring

    @Test("Monitors single provider and returns snapshot")
    func monitorsSingleProviderAndReturnsSnapshot() async throws {
        // Given
        let mockProbe = MockUsageProbePort()
        let expectedSnapshot = UsageSnapshot(
            provider: .claude,
            quotas: [
                UsageQuota(percentRemaining: 65, quotaType: .session, provider: .claude),
                UsageQuota(percentRemaining: 35, quotaType: .weekly, provider: .claude),
            ],
            capturedAt: Date()
        )

        given(mockProbe).provider.willReturn(.claude)
        given(mockProbe).isAvailable().willReturn(true)
        given(mockProbe).probe().willReturn(expectedSnapshot)

        let monitor = QuotaMonitor(probes: [mockProbe])

        // When
        let snapshots = try await monitor.refreshAll()

        // Then
        #expect(snapshots.count == 1)
        #expect(snapshots[.claude]?.quotas.count == 2)
        #expect(snapshots[.claude]?.quota(for: .session)?.percentRemaining == 65)
    }

    @Test("Returns empty when provider is unavailable")
    func returnsEmptyWhenProviderUnavailable() async throws {
        // Given
        let mockProbe = MockUsageProbePort()
        given(mockProbe).provider.willReturn(.claude)
        given(mockProbe).isAvailable().willReturn(false)

        let monitor = QuotaMonitor(probes: [mockProbe])

        // When
        let snapshots = try await monitor.refreshAll()

        // Then
        #expect(snapshots.isEmpty)
    }

    // MARK: - Multiple Provider Monitoring

    @Test("Monitors multiple providers concurrently")
    func monitorsMultipleProvidersConcurrently() async throws {
        // Given
        let claudeProbe = MockUsageProbePort()
        let codexProbe = MockUsageProbePort()

        let claudeSnapshot = UsageSnapshot(
            provider: .claude,
            quotas: [UsageQuota(percentRemaining: 70, quotaType: .session, provider: .claude)],
            capturedAt: Date()
        )
        let codexSnapshot = UsageSnapshot(
            provider: .codex,
            quotas: [UsageQuota(percentRemaining: 40, quotaType: .session, provider: .codex)],
            capturedAt: Date()
        )

        given(claudeProbe).provider.willReturn(.claude)
        given(claudeProbe).isAvailable().willReturn(true)
        given(claudeProbe).probe().willReturn(claudeSnapshot)

        given(codexProbe).provider.willReturn(.codex)
        given(codexProbe).isAvailable().willReturn(true)
        given(codexProbe).probe().willReturn(codexSnapshot)

        let monitor = QuotaMonitor(probes: [claudeProbe, codexProbe])

        // When
        let snapshots = try await monitor.refreshAll()

        // Then
        #expect(snapshots.count == 2)
        #expect(snapshots[.claude]?.quota(for: .session)?.percentRemaining == 70)
        #expect(snapshots[.codex]?.quota(for: .session)?.percentRemaining == 40)
    }

    @Test("Partial failure does not affect other providers")
    func partialFailureDoesNotAffectOtherProviders() async throws {
        // Given
        let claudeProbe = MockUsageProbePort()
        let codexProbe = MockUsageProbePort()

        let claudeSnapshot = UsageSnapshot(
            provider: .claude,
            quotas: [UsageQuota(percentRemaining: 70, quotaType: .session, provider: .claude)],
            capturedAt: Date()
        )

        given(claudeProbe).provider.willReturn(.claude)
        given(claudeProbe).isAvailable().willReturn(true)
        given(claudeProbe).probe().willReturn(claudeSnapshot)

        given(codexProbe).provider.willReturn(.codex)
        given(codexProbe).isAvailable().willReturn(true)
        given(codexProbe).probe().willThrow(ProbeError.timeout)

        let monitor = QuotaMonitor(probes: [claudeProbe, codexProbe])

        // When
        let snapshots = try await monitor.refreshAll()

        // Then - Claude succeeded, Codex failed but didn't affect Claude
        #expect(snapshots.count == 1)
        #expect(snapshots[.claude] != nil)
        #expect(snapshots[.codex] == nil)
    }

    // MARK: - Status Change Detection

    @Test("Detects status change from healthy to warning")
    func detectsStatusChangeFromHealthyToWarning() async throws {
        // Given
        let mockProbe = MockUsageProbePort()
        let mockObserver = MockQuotaObserverPort()

        // First snapshot - healthy
        let healthySnapshot = UsageSnapshot(
            provider: .claude,
            quotas: [UsageQuota(percentRemaining: 60, quotaType: .session, provider: .claude)],
            capturedAt: Date()
        )

        // Second snapshot - warning
        let warningSnapshot = UsageSnapshot(
            provider: .claude,
            quotas: [UsageQuota(percentRemaining: 30, quotaType: .session, provider: .claude)],
            capturedAt: Date()
        )

        var callCount = 0
        given(mockProbe).provider.willReturn(.claude)
        given(mockProbe).isAvailable().willReturn(true)
        given(mockProbe).probe().willProduce {
            callCount += 1
            return callCount == 1 ? healthySnapshot : warningSnapshot
        }

        given(mockObserver).onSnapshotUpdated(.any).willReturn()
        given(mockObserver).onStatusChanged(provider: .any, oldStatus: .any, newStatus: .any).willReturn()

        let monitor = QuotaMonitor(probes: [mockProbe], observer: mockObserver)

        // When
        _ = try await monitor.refreshAll() // First refresh - healthy
        _ = try await monitor.refreshAll() // Second refresh - warning

        // Then
        verify(mockObserver).onStatusChanged(
            provider: .value(.claude),
            oldStatus: .value(.healthy),
            newStatus: .value(.warning)
        ).called(.once)
    }

    // MARK: - Current Snapshot Access

    @Test("Returns current snapshot for provider")
    func returnsCurrentSnapshotForProvider() async throws {
        // Given
        let mockProbe = MockUsageProbePort()
        let snapshot = UsageSnapshot(
            provider: .claude,
            quotas: [UsageQuota(percentRemaining: 50, quotaType: .session, provider: .claude)],
            capturedAt: Date()
        )

        given(mockProbe).provider.willReturn(.claude)
        given(mockProbe).isAvailable().willReturn(true)
        given(mockProbe).probe().willReturn(snapshot)

        let monitor = QuotaMonitor(probes: [mockProbe])
        _ = try await monitor.refreshAll()

        // When
        let currentSnapshot = await monitor.snapshot(for: .claude)

        // Then
        #expect(currentSnapshot?.quota(for: .session)?.percentRemaining == 50)
    }

    @Test("Returns nil for unmonitored provider")
    func returnsNilForUnmonitoredProvider() async {
        // Given
        let monitor = QuotaMonitor(probes: [])

        // When
        let snapshot = await monitor.snapshot(for: .claude)

        // Then
        #expect(snapshot == nil)
    }
}
