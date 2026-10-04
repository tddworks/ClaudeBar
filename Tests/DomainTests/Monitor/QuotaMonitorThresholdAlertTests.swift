import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

/// Tests for user-configured below-threshold alerts flowing through
/// QuotaMonitor's refresh path (issue #68).
///
/// Uses hand-rolled recording doubles rather than Mockable so the assertions
/// stay on resulting state.
@Suite
@MainActor
struct QuotaMonitorThresholdAlertTests {

    private struct TestClock: Clock {
        func sleep(for duration: Duration) async throws {}
        func sleep(nanoseconds: UInt64) async throws {}
    }

    /// Records everything the monitor asks of its alerter.
    private actor RecordingAlerter: QuotaAlerter {
        struct ThresholdAlert: Equatable {
            let providerId: String
            let percentRemaining: Double
            let threshold: Double
        }

        struct StatusAlert: Equatable {
            let providerId: String
            let previous: QuotaStatus
            let current: QuotaStatus
        }

        private var thresholdAlertsStorage: [ThresholdAlert] = []
        private var statusAlertsStorage: [StatusAlert] = []

        var thresholdAlerts: [ThresholdAlert] { thresholdAlertsStorage }
        var statusAlerts: [StatusAlert] { statusAlertsStorage }

        func requestPermission() async -> Bool { true }

        func alert(providerId: String, previousStatus: QuotaStatus, currentStatus: QuotaStatus) async {
            statusAlertsStorage.append(
                StatusAlert(providerId: providerId, previous: previousStatus, current: currentStatus)
            )
        }

        func alertThresholdCrossed(providerId: String, percentRemaining: Double, threshold: QuotaAlertThreshold) async {
            thresholdAlertsStorage.append(
                ThresholdAlert(providerId: providerId, percentRemaining: percentRemaining, threshold: threshold.percent)
            )
        }
    }

    /// Returns one fixed snapshot, the way a probe would.
    private struct StubProbe: UsageProbe {
        let snapshot: UsageSnapshot

        func probe() async throws -> UsageSnapshot { snapshot }
        func isAvailable() async -> Bool { true }
    }

    /// A probe whose reported percentage the test steps between refreshes.
    private final class SteppedProbe: UsageProbe, @unchecked Sendable {
        var percent: Double
        init(percent: Double) { self.percent = percent }

        func probe() async throws -> UsageSnapshot {
            UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: percent, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            )
        }
        func isAvailable() async -> Bool { true }
    }

    /// Settings mock: the provider enabled. The monitor itself gets no
    /// settings repository, so only the provider reads this.
    private func makeSettingsRepository() -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(mock).isEnabled(forProvider: .any).willReturn(true)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        return mock
    }

    /// In-memory stand-in for the threshold settings repository.
    private final class StubThresholdSettings: QuotaAlertSettingsRepository, @unchecked Sendable {
        var thresholds: [QuotaAlertThreshold]
        init(_ percents: [Double]) {
            self.thresholds = percents.map(QuotaAlertThreshold.init(percent:))
        }
        func alertThresholds() -> [QuotaAlertThreshold] { thresholds }
        func setAlertThresholds(_ thresholds: [QuotaAlertThreshold]) { self.thresholds = thresholds }
    }

    private func makeMonitor(
        percentRemaining: Double,
        thresholds: [Double],
        alerter: RecordingAlerter
    ) -> QuotaMonitor {
        let probe = StubProbe(snapshot: UsageSnapshot(
            providerId: "claude",
            quotas: [UsageQuota(percentRemaining: percentRemaining, quotaType: .session, providerId: "claude")],
            capturedAt: Date()
        ))
        let provider = StubClaudeProvider(probe: probe, settingsRepository: makeSettingsRepository())
        return QuotaMonitor(
            providers: AIProviders(providers: [provider]),
            alerter: alerter,
            clock: TestClock(),
            alertThresholds: StubThresholdSettings(thresholds)
        )
    }

    @Test
    func `no threshold alert while percent stays above the threshold`() async {
        let alerter = RecordingAlerter()
        let monitor = makeMonitor(percentRemaining: 70, thresholds: [35], alerter: alerter)

        await monitor.refresh(providerId: "claude")

        #expect(await alerter.thresholdAlerts.isEmpty)
    }

    @Test
    func `threshold alert fires when percent crosses below configured threshold`() async {
        let alerter = RecordingAlerter()
        let monitor = makeMonitor(percentRemaining: 30, thresholds: [35], alerter: alerter)

        await monitor.refresh(providerId: "claude")

        #expect(await alerter.thresholdAlerts == [
            RecordingAlerter.ThresholdAlert(providerId: "claude", percentRemaining: 30, threshold: 35)
        ])
    }

    @Test
    func `threshold alert fires once across repeated refreshes below the threshold`() async {
        let alerter = RecordingAlerter()
        let monitor = makeMonitor(percentRemaining: 30, thresholds: [35], alerter: alerter)

        await monitor.refresh(providerId: "claude")
        await monitor.refresh(providerId: "claude")
        await monitor.refresh(providerId: "claude")

        #expect(await alerter.thresholdAlerts.count == 1)
    }

    @Test
    func `multiple thresholds each alert once as they are crossed`() async {
        let alerter = RecordingAlerter()
        let probe = SteppedProbe(percent: 65)
        let provider = StubClaudeProvider(probe: probe, settingsRepository: makeSettingsRepository())
        let monitor = QuotaMonitor(
            providers: AIProviders(providers: [provider]),
            alerter: alerter,
            clock: TestClock(),
            alertThresholds: StubThresholdSettings([60, 35, 10])
        )

        // Above every threshold.
        await monitor.refresh(providerId: "claude")
        #expect(await alerter.thresholdAlerts.isEmpty)

        // Steps down through each threshold: one firing per step.
        probe.percent = 55
        await monitor.refresh(providerId: "claude")
        #expect(await alerter.thresholdAlerts.map(\.threshold) == [60])

        probe.percent = 30
        await monitor.refresh(providerId: "claude")
        #expect(await alerter.thresholdAlerts.map(\.threshold) == [60, 35])

        probe.percent = 5
        await monitor.refresh(providerId: "claude")
        #expect(await alerter.thresholdAlerts.map(\.threshold) == [60, 35, 10])

        // Still below all of them: no refires.
        probe.percent = 2
        await monitor.refresh(providerId: "claude")
        #expect(await alerter.thresholdAlerts.map(\.threshold) == [60, 35, 10])
    }

    @Test
    func `no threshold alerts when no thresholds configured`() async {
        let alerter = RecordingAlerter()
        let monitor = makeMonitor(percentRemaining: 5, thresholds: [], alerter: alerter)

        await monitor.refresh(providerId: "claude")

        #expect(await alerter.thresholdAlerts.isEmpty)
    }

    @Test
    func `fixed degradation alerts still fire alongside threshold alerts`() async {
        let alerter = RecordingAlerter()
        let monitor = makeMonitor(percentRemaining: 15, thresholds: [35], alerter: alerter)

        await monitor.refresh(providerId: "claude")

        // Built-in healthy -> critical degradation alert...
        #expect(await alerter.statusAlerts == [
            RecordingAlerter.StatusAlert(providerId: "claude", previous: .healthy, current: .critical)
        ])
        // ...and the user's own 35% threshold alert.
        #expect(await alerter.thresholdAlerts == [
            RecordingAlerter.ThresholdAlert(providerId: "claude", percentRemaining: 15, threshold: 35)
        ])
    }

    @Test
    func `monitor without threshold settings never alerts thresholds`() async {
        let alerter = RecordingAlerter()
        let probe = StubProbe(snapshot: UsageSnapshot(
            providerId: "claude",
            quotas: [UsageQuota(percentRemaining: 10, quotaType: .session, providerId: "claude")],
            capturedAt: Date()
        ))
        let provider = StubClaudeProvider(probe: probe, settingsRepository: makeSettingsRepository())
        let monitor = QuotaMonitor(
            providers: AIProviders(providers: [provider]),
            alerter: alerter,
            clock: TestClock()
        )

        await monitor.refresh(providerId: "claude")

        #expect(await alerter.thresholdAlerts.isEmpty)
    }
}
