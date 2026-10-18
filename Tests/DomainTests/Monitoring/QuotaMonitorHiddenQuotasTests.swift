import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

/// Issue #140: hidden quota keys must stop driving the monitor's aggregates —
/// lowest quota, overall status, selected-provider status and alerts. A hidden
/// "Gemini Flash 2.0" must not color the provider.
@Suite
@MainActor
struct QuotaMonitorHiddenQuotasTests {
    private struct TestClock: Clock {
        func sleep(for duration: Duration) async throws {}
        func sleep(nanoseconds: UInt64) async throws {}
    }

    /// Chicago-school alerter: records what it was told, tests assert state.
    private actor RecordingAlerter: QuotaAlerter {
        private(set) var alerts: [(providerId: String, previous: QuotaStatus, current: QuotaStatus)] = []

        func requestPermission() async -> Bool { true }

        func alert(providerId: String, previousStatus: QuotaStatus, currentStatus: QuotaStatus) async {
            alerts.append((providerId, previousStatus, currentStatus))
        }
    }

    /// Gemini-style snapshot: session and weekly healthy, flash critical (10%).
    private func makeGeminiProbe() -> MockUsageProbe {
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(UsageSnapshot(
            providerId: "gemini",
            quotas: [
                UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "gemini"),
                UsageQuota(percentRemaining: 70, quotaType: .weekly, providerId: "gemini"),
                UsageQuota(percentRemaining: 10, quotaType: .modelSpecific("gemini-2.0-flash"), providerId: "gemini"),
            ],
            capturedAt: Date()
        ))
        return probe
    }

    private func makeSettings(hiddenKeys: Set<String>) -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(mock).isEnabled(forProvider: .any).willReturn(true)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        given(mock).hiddenQuotaKeys(forProvider: .any).willReturn(hiddenKeys)
        given(mock).providerOrder().willReturn([])
        given(mock).setProviderOrder(.any).willReturn()
        return mock
    }

    private func makeRefreshedGeminiMonitor(
        hiddenKeys: Set<String>,
        alerter: (any QuotaAlerter)? = nil
    ) async -> (QuotaMonitor, MockProviderSettingsRepository) {
        let settings = makeSettings(hiddenKeys: hiddenKeys)
        let providerProduct = stubbedProduct("gemini", probe: makeGeminiProbe(), settings: settings)
        let provider = providerProduct.defaultAccount
        let monitor = QuotaMonitor(
            providers: kept([providerProduct]),
            alerter: alerter,
            clock: TestClock(),
            settingsRepository: settings
        )
        await monitor.refresh(providerId: "gemini")
        return (monitor, settings)
    }

    // MARK: - Lowest Quota

    @Test
    func `should headline the lowest quota the person can see, not a hidden one (#140)`() async {
        // Given — the hidden flash model is the lowest of all
        let (monitor, _) = await makeRefreshedGeminiMonitor(hiddenKeys: ["model:gemini-2.0-flash"])

        // When & Then — the headline number promotes to the next-lowest visible quota
        #expect(monitor.lowestQuota()?.quotaType == .weekly)

        // And the same snapshot without hiding picks the flash model
        let (unhidden, _) = await makeRefreshedGeminiMonitor(hiddenKeys: [])
        #expect(unhidden.lowestQuota()?.quotaType == .modelSpecific("gemini-2.0-flash"))
    }

    @Test
    func `should show every quota rather than nothing when settings hide them all`() async {
        let (monitor, _) = await makeRefreshedGeminiMonitor(
            hiddenKeys: ["session", "weekly", "model:gemini-2.0-flash"]
        )

        #expect(monitor.lowestQuota()?.quotaType == .modelSpecific("gemini-2.0-flash"))
    }

    // MARK: - One usage for every surface

    @Test
    func `should leave a hidden quota out of the usage everywhere shows, while keeping it read`() async throws {
        let (monitor, _) = await makeRefreshedGeminiMonitor(hiddenKeys: ["model:gemini-2.0-flash"])
        let gemini = try #require(monitor.login(id: "gemini"))

        let usage = try #require(monitor.usage(of: gemini))

        #expect(usage.quotas.map(\.quotaType) == [.session, .weekly])
        #expect(gemini.snapshot?.quotas.count == 3)
    }

    @Test
    func `should leave a quota out and stop it colouring the status at once when the person hides it`() async throws {
        let (monitor, settings) = await makeRefreshedGeminiMonitor(hiddenKeys: [])
        given(settings).setHiddenQuotaKeys(.any, forProvider: .any).willReturn()
        let gemini = try #require(monitor.login(id: "gemini"))

        #expect(monitor.setQuota("model:gemini-2.0-flash", hidden: true, for: gemini))

        #expect(monitor.hiddenQuotaKeys(for: gemini) == ["model:gemini-2.0-flash"])
        #expect(monitor.overallStatus == .healthy)
        #expect(monitor.usage(of: gemini)?.quotas.count == 2)
    }

    @Test
    func `should refuse to hide the last quota the person can see`() async throws {
        let (monitor, settings) = await makeRefreshedGeminiMonitor(hiddenKeys: ["session", "weekly"])
        given(settings).setHiddenQuotaKeys(.any, forProvider: .any).willReturn()
        let gemini = try #require(monitor.login(id: "gemini"))

        #expect(monitor.setQuota("model:gemini-2.0-flash", hidden: true, for: gemini) == false)

        #expect(monitor.hiddenQuotaKeys(for: gemini) == ["session", "weekly"])
        #expect(monitor.usage(of: gemini)?.quotas.map(\.quotaType) == [.modelSpecific("gemini-2.0-flash")])
    }

    @Test
    func `should bring a quota back, status and all, when the person shows it again`() async throws {
        let (monitor, settings) = await makeRefreshedGeminiMonitor(hiddenKeys: ["model:gemini-2.0-flash"])
        given(settings).setHiddenQuotaKeys(.any, forProvider: .any).willReturn()
        let gemini = try #require(monitor.login(id: "gemini"))

        #expect(monitor.setQuota("model:gemini-2.0-flash", hidden: false, for: gemini))

        #expect(monitor.hiddenQuotaKeys(for: gemini).isEmpty)
        #expect(monitor.overallStatus == .critical)
    }

    @Test
    func `should count every quota when there are no saved settings`() async {
        // Given — no settings repository wired (existing call sites)
        let settings = makeSettings(hiddenKeys: [])
        let providerProduct = stubbedProduct("gemini", probe: makeGeminiProbe(), settings: settings)
        let provider = providerProduct.defaultAccount
        let monitor = QuotaMonitor(
            providers: kept([providerProduct]),
            clock: TestClock()
        )
        await monitor.refresh(providerId: "gemini")

        // When & Then — behaviour is unchanged: all quotas count
        #expect(monitor.lowestQuota()?.quotaType == .modelSpecific("gemini-2.0-flash"))
        #expect(monitor.overallStatus == .critical)
    }

    // MARK: - Overall Status

    @Test
    func `should keep the menu bar healthy when only a hidden quota is critical`() async {
        // Given & When & Then — a hidden critical quota must not color the status
        let (hidden, _) = await makeRefreshedGeminiMonitor(hiddenKeys: ["model:gemini-2.0-flash"])
        #expect(hidden.overallStatus == .healthy)

        let (visible, _) = await makeRefreshedGeminiMonitor(hiddenKeys: [])
        #expect(visible.overallStatus == .critical)
    }

    @Test
    func `should keep the selected provider healthy when only a hidden quota is critical`() async {
        let (monitor, _) = await makeRefreshedGeminiMonitor(hiddenKeys: ["model:gemini-2.0-flash"])

        #expect(monitor.selectedProviderId == "gemini")
        #expect(monitor.selectedProviderStatus == .healthy)
    }

    // MARK: - Alerts

    @Test
    func `should not alert the person when only a hidden quota turns critical`() async {
        // Given — the critical flash model is hidden
        let alerter = RecordingAlerter()
        let (monitor, _) = await makeRefreshedGeminiMonitor(
            hiddenKeys: ["model:gemini-2.0-flash"],
            alerter: alerter
        )
        _ = monitor

        // When & Then — the visible status is healthy, same as before the
        // refresh, so there is nothing to alert about
        #expect(await alerter.alerts.isEmpty)
    }

    @Test
    func `should alert the person when a quota they can see turns critical`() async {
        // Given — nothing hidden, so the snapshot is critical
        let alerter = RecordingAlerter()
        let (monitor, _) = await makeRefreshedGeminiMonitor(hiddenKeys: [], alerter: alerter)
        _ = monitor

        // Then — healthy → critical on first refresh
        #expect(await alerter.alerts.count == 1)
        #expect(await alerter.alerts.first?.providerId == "gemini")
        #expect(await alerter.alerts.first?.previous == .healthy)
        #expect(await alerter.alerts.first?.current == .critical)
    }
}
