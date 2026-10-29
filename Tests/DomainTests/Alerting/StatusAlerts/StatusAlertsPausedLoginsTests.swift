import Foundation
import Testing
import Mockable
@testable import Domain
@testable import Infrastructure

/// A login paused from the popover is out of every judgement, alerts included
/// (docs/features/providers/multi-account/design.md §3.5). The rest of what a
/// pause does is the Monitor's, in `MonitoringTests`' `PausedLoginsTests`.
@MainActor
@Suite
struct StatusAlertsPausedLoginsTests {
    private struct TestClock: Clock {
        func sleep(for duration: Duration) async throws {}
        func sleep(nanoseconds: UInt64) async throws {}
    }

    private func quota(_ left: Double) -> UsageQuota {
        UsageQuota(percentRemaining: left, quotaType: .session, providerId: "p")
    }

    private func snapshot(_ quotas: UsageQuota...) -> UsageSnapshot {
        UsageSnapshot(providerId: "p", quotas: quotas, capturedAt: Date())
    }

    /// What the person was told, so a test can read it.
    private final class Told {
        let destination = RecordingDestination()
        var alerts: [Alert] { destination.alerts }
    }

    /// A fetch that waits for `open()` — so a test can pause a login while its
    /// refresh is still in flight.
    private actor GatedProbe: UsageProbe {
        private let usage: UsageSnapshot
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        init(_ usage: UsageSnapshot) { self.usage = usage }

        func isAvailable() async -> Bool { true }

        func probe() async throws -> UsageSnapshot {
            if !isOpen { await withCheckedContinuation { waiters.append($0) } }
            return usage
        }

        func open() {
            isOpen = true
            let waiting = waiters
            waiters = []
            waiting.forEach { $0.resume() }
        }
    }

    @Test
    func `should publish nothing for a login paused while its refresh is in flight`() async throws {
        // Given — a fetch held open, so the login can be paused while it runs
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let probe = GatedProbe(snapshot(quota(9)))
        let product = stubbedProduct("claude", probe: probe, settings: settings)
        let told = Told()
        let monitor = QuotaMonitor(providers: kept([product]), clock: TestClock())
        StatusAlerts(destination: told.destination).follow(monitor)

        // When — she pauses the login, and only then lets the fetch land
        let inFlight = Task { await monitor.refreshAll() }
        try await Task.sleep(for: .milliseconds(50))
        monitor.pause(product.defaultAccount)
        await probe.open()
        await inFlight.value

        // Then — nothing was fetched into it, and nobody was paged about it
        #expect(product.defaultAccount.snapshot == nil)
        #expect(told.alerts.isEmpty)
    }
}
