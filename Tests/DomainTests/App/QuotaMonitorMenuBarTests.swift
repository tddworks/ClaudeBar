import Testing
import Foundation
import Mockable
@testable import Domain

/// The menu bar's readouts, built from what the Monitor shows
/// (`QuotaMonitor+MenuBar.swift`). The Monitor itself is `MonitoringTests`'.
@Suite
@MainActor
struct QuotaMonitorMenuBarTests {
    private struct TestClock: Clock {
        func sleep(for duration: Duration) async throws {}
        func sleep(nanoseconds: UInt64) async throws {}
    }

    private actor RefreshCounter {
        private var value = 0

        func increment() -> Int {
            value += 1
            return value
        }

        func count() -> Int {
            value
        }
    }

    private final class CountingUsageProbe: UsageProbe, @unchecked Sendable {
        let providerId: String
        let counter = RefreshCounter()

        init(providerId: String) {
            self.providerId = providerId
        }

        func probe() async throws -> UsageSnapshot {
            let count = await counter.increment()
            return UsageSnapshot(
                providerId: providerId,
                quotas: [
                    UsageQuota(
                        percentRemaining: Double(100 - count),
                        quotaType: .session,
                        providerId: providerId
                    ),
                ],
                capturedAt: Date()
            )
        }

        func isAvailable() async -> Bool {
            true
        }
    }

    private func makeMonitor(providers: Providers) -> QuotaMonitor {
        QuotaMonitor(providers: providers, clock: TestClock())
    }

    /// Creates a mock settings repository that returns true for all providers
    private func makeSettingsRepository() -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(mock).isEnabled(forProvider: .any).willReturn(true)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        return mock
    }

    @Test
    func `should show the chosen weekly quota as 65% used, in warning, in the menu bar`() async {
        // Given
        let settings = makeSettingsRepository()
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(UsageSnapshot(
            providerId: "claude",
            quotas: [
                UsageQuota(percentRemaining: 75, quotaType: .session, providerId: "claude"),
                UsageQuota(percentRemaining: 35, quotaType: .weekly, providerId: "claude"),
            ],
            capturedAt: Date()
        ))
        let providerProduct = stubbedProduct("claude", probe: probe, settings: settings)
        let provider = providerProduct.defaultAccount
        let monitor = makeMonitor(providers: kept([providerProduct]))

        // When
        await monitor.refresh(providerId: "claude")
        let display = monitor.menuBarPercentageDisplay(
            providerId: "claude",
            quotaKey: "weekly",
            mode: .used
        )

        // Then
        #expect(display?.text == "65%")
        #expect(display?.status == .warning)
    }

    @Test
    func `should show no menu bar percentage before the provider has any quotas`() {
        // Given
        let settings = makeSettingsRepository()
        let providerProduct = stubbedProduct("claude", probe: MockUsageProbe(), settings: settings)
        let provider = providerProduct.defaultAccount
        let monitor = makeMonitor(providers: kept([providerProduct]))

        // When
        let display = monitor.menuBarPercentageDisplay(
            providerId: "claude",
            quotaKey: "session",
            mode: .remaining
        )

        // Then
        #expect(display == nil)
    }

    @Test
    func `should show the session's reset as 3:58 in the menu bar`() async {
        // Given - claude session quota with reset ~3h 58m away
        let settings = makeSettingsRepository()
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(UsageSnapshot(
            providerId: "claude",
            quotas: [
                UsageQuota(
                    percentRemaining: 75,
                    quotaType: .session,
                    providerId: "claude",
                    resetsAt: Date().addingTimeInterval(3.0 * 3600 + 58.0 * 60 + 30)
                ),
            ],
            capturedAt: Date()
        ))
        let providerProduct = stubbedProduct("claude", probe: probe, settings: settings)
        let provider = providerProduct.defaultAccount
        let monitor = makeMonitor(providers: kept([providerProduct]))

        // When
        await monitor.refresh(providerId: "claude")
        let display = monitor.menuBarDurationDisplay(
            providerId: "claude",
            quotaKey: "session"
        )

        // Then
        #expect(display?.text == "3:58")
        #expect(display?.status == .healthy)
    }

    @Test
    func `should show no menu bar countdown before the provider has any quotas`() {
        // Given
        let settings = makeSettingsRepository()
        let providerProduct = stubbedProduct("claude", probe: MockUsageProbe(), settings: settings)
        let provider = providerProduct.defaultAccount
        let monitor = makeMonitor(providers: kept([providerProduct]))

        // When
        let display = monitor.menuBarDurationDisplay(
            providerId: "claude",
            quotaKey: "session"
        )

        // Then
        #expect(display == nil)
    }

    @Test
    func `should name each extra menu bar provider beside its first quota, and show nothing when percentages are off`() async {
        let monitor = await makeRefreshedClaudeMonitor(quotas: [
            UsageQuota(percentRemaining: 35, quotaType: .weekly, providerId: "claude"),
        ])
        let labels = monitor.additionalMenuBarLabels(
            providerIds: ["claude", "missing"], showPercentage: true,
            showDuration: false, mode: .remaining
        )
        #expect(labels.map(\.text) == ["Claude 35%"])
        #expect(labels.first?.providerId == "claude")
        #expect(labels.first?.label.text == "35%")
        #expect(labels.first?.status == .warning)
        #expect(monitor.additionalMenuBarLabels(
            providerIds: ["claude"], showPercentage: false,
            showDuration: false, mode: .remaining
        ).isEmpty)
    }

    @Test
    func `should show extra menu bar providers once each, in the chosen order, leaving out disabled ones`() async {
        let settings = makeSettingsRepository()
        let claudeProduct = stubbedProduct("claude", probe: CountingUsageProbe(providerId: "claude"), settings: settings)
        let claude = claudeProduct.defaultAccount
        let codexProduct = stubbedProduct("codex", probe: CountingUsageProbe(providerId: "codex"), settings: settings)
        let codex = codexProduct.defaultAccount
        let monitor = makeMonitor(providers: kept([claudeProduct, codexProduct]))
        await monitor.refresh(providerId: "claude")
        await monitor.refresh(providerId: "codex")
        #expect(monitor.additionalMenuBarLabels(
            providerIds: ["codex", "codex", "claude"], showPercentage: true,
            showDuration: false, mode: .used
        ).map(\.text) == ["Codex 1%", "Claude 1%"])
        codex.isPaused = true
        #expect(monitor.additionalMenuBarLabels(
            providerIds: ["codex", "claude"], showPercentage: true,
            showDuration: false, mode: .remaining
        ).map(\.text) == ["Claude 99%"])
    }

    @Test
    func `should show an extra menu bar provider as a dash beside its name before its first quotas arrive`() {
        let providerProduct = stubbedProduct(
            "claude", probe: CountingUsageProbe(providerId: "claude"), settings: makeSettingsRepository()
        )
        let provider = providerProduct.defaultAccount
        let monitor = makeMonitor(providers: kept([providerProduct]))
        #expect(monitor.additionalMenuBarLabels(
            providerIds: ["claude"], showPercentage: true, showDuration: false, mode: .remaining
        ).map(\.text) == ["Claude —"])
    }

    @Test
    func `should show an extra menu bar provider with its own primary, secondary and stacked choices`() async {
        let monitor = await makeRefreshedClaudeMonitor(quotas: [
            UsageQuota(percentRemaining: 75, quotaType: .session, providerId: "claude"),
            UsageQuota(percentRemaining: 35, quotaType: .weekly, providerId: "claude"),
        ])
        let labels = monitor.additionalMenuBarLabels(
            providerIds: ["claude"],
            configurations: ["claude": MenuBarProviderSettings(primaryQuotaKey: "weekly", secondaryQuotaKey: "session", stacked: true, stackedSize: "large")],
            showPercentage: true, showDuration: false, mode: .remaining
        )
        #expect(labels.first?.label.text == "7d 35% | 5h 75%")
        #expect(labels.first?.label.segments.count == 2)
        #expect(labels.first?.stacked == true)
        #expect(labels.first?.stackedSize == .large)
        #expect(monitor.menuBarLabel(providerId: "claude", primaryQuotaKey: "", showPercentage: true,
                                    showDuration: false, mode: .remaining)?.text == "75%")
    }

    // MARK: - Menu Bar Label (single + dual window)

    /// Builds a Claude-only monitor, refreshed once with the given quotas.
    private func makeRefreshedClaudeMonitor(quotas: [UsageQuota]) async -> QuotaMonitor {
        let settings = makeSettingsRepository()
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(UsageSnapshot(
            providerId: "claude",
            quotas: quotas,
            capturedAt: Date()
        ))
        let providerProduct = stubbedProduct("claude", probe: probe, settings: settings)
        let provider = providerProduct.defaultAccount
        let monitor = makeMonitor(providers: kept([providerProduct]))
        await monitor.refresh(providerId: "claude")
        return monitor
    }

    @Test
    func `should show one window without a prefix when no second window is chosen`() async {
        // Given
        let monitor = await makeRefreshedClaudeMonitor(quotas: [
            UsageQuota(percentRemaining: 75, quotaType: .session, providerId: "claude"),
            UsageQuota(percentRemaining: 35, quotaType: .weekly, providerId: "claude"),
        ])

        // When
        let label = monitor.menuBarLabel(
            providerId: "claude",
            primaryQuotaKey: "session",
            secondaryQuotaKey: "",
            showPercentage: true,
            showDuration: false,
            mode: .remaining
        )

        // Then — unchanged single-window output
        #expect(label?.text == "75%")
        #expect(label?.status == .healthy)
    }

    @Test
    func `should show both windows prefixed 5h and 7d, in the worse status, when two are chosen`() async {
        // Given — session 75% (healthy), weekly 35% (warning)
        let monitor = await makeRefreshedClaudeMonitor(quotas: [
            UsageQuota(percentRemaining: 75, quotaType: .session, providerId: "claude"),
            UsageQuota(percentRemaining: 35, quotaType: .weekly, providerId: "claude"),
        ])

        // When
        let label = monitor.menuBarLabel(
            providerId: "claude",
            primaryQuotaKey: "session",
            secondaryQuotaKey: "weekly",
            showPercentage: true,
            showDuration: false,
            mode: .remaining
        )

        // Then — both windows, prefixed, worst status (warning) wins
        #expect(label?.text == "5h 75% | 7d 35%")
        #expect(label?.status == .warning)
    }

    @Test
    func `should show one window without a prefix when the second window is the same as the first`() async {
        // Given
        let monitor = await makeRefreshedClaudeMonitor(quotas: [
            UsageQuota(percentRemaining: 75, quotaType: .session, providerId: "claude"),
        ])

        // When — secondary same as primary
        let label = monitor.menuBarLabel(
            providerId: "claude",
            primaryQuotaKey: "session",
            secondaryQuotaKey: "session",
            showPercentage: true,
            showDuration: false,
            mode: .remaining
        )

        // Then — deduped to a single unprefixed window
        #expect(label?.text == "75%")
    }

    @Test
    func `should show the first window alone when the provider has no quota for the second`() async {
        // Given — only session quota present, but weekly requested as secondary
        let monitor = await makeRefreshedClaudeMonitor(quotas: [
            UsageQuota(percentRemaining: 75, quotaType: .session, providerId: "claude"),
        ])

        // When
        let label = monitor.menuBarLabel(
            providerId: "claude",
            primaryQuotaKey: "session",
            secondaryQuotaKey: "weekly",
            showPercentage: true,
            showDuration: false,
            mode: .remaining
        )

        // Then — no secondary data, primary shown alone without prefix
        #expect(label?.text == "75%")
    }

    @Test
    func `should show no menu bar label when neither percentage nor countdown is on`() async {
        // Given
        let monitor = await makeRefreshedClaudeMonitor(quotas: [
            UsageQuota(percentRemaining: 75, quotaType: .session, providerId: "claude"),
            UsageQuota(percentRemaining: 35, quotaType: .weekly, providerId: "claude"),
        ])

        // When
        let label = monitor.menuBarLabel(
            providerId: "claude",
            primaryQuotaKey: "session",
            secondaryQuotaKey: "weekly",
            showPercentage: false,
            showDuration: false,
            mode: .remaining
        )

        // Then
        #expect(label == nil)
    }

    @Test
    func `should give a stacked menu bar one line when one window is chosen`() async {
        // Given
        let monitor = await makeRefreshedClaudeMonitor(quotas: [
            UsageQuota(percentRemaining: 75, quotaType: .session, providerId: "claude"),
        ])

        // When
        let label = monitor.menuBarLabel(
            providerId: "claude",
            primaryQuotaKey: "session",
            secondaryQuotaKey: "",
            showPercentage: true,
            showDuration: false,
            mode: .remaining
        )

        // Then: one segment mirroring the joined text, so segment-based
        // renderers read the same source as the single-line label
        #expect(label?.segments == [
            MenuBarLabel.Segment(text: "75%", status: .healthy),
        ])
    }

    @Test
    func `should give a stacked menu bar one line per window, each in its own status`() async {
        // Given: session 75% (healthy), weekly 35% (warning)
        let monitor = await makeRefreshedClaudeMonitor(quotas: [
            UsageQuota(percentRemaining: 75, quotaType: .session, providerId: "claude"),
            UsageQuota(percentRemaining: 35, quotaType: .weekly, providerId: "claude"),
        ])

        // When
        let label = monitor.menuBarLabel(
            providerId: "claude",
            primaryQuotaKey: "session",
            secondaryQuotaKey: "weekly",
            showPercentage: true,
            showDuration: false,
            mode: .remaining
        )

        // Then: joined text stays byte-identical (it doubles as the tooltip),
        // while each segment keeps its own prefixed text and per-window status
        // so a stacked renderer can tint the two lines independently
        #expect(label?.text == "5h 75% | 7d 35%")
        #expect(label?.status == .warning)
        #expect(label?.segments == [
            MenuBarLabel.Segment(text: "5h 75%", status: .healthy),
            MenuBarLabel.Segment(text: "7d 35%", status: .warning),
        ])
    }

    @Test
    func `should give a stacked menu bar the countdown line when only the countdown is on`() async {
        // Given: session quota with reset ~3h 58m away
        let monitor = await makeRefreshedClaudeMonitor(quotas: [
            UsageQuota(
                percentRemaining: 75,
                quotaType: .session,
                providerId: "claude",
                resetsAt: Date().addingTimeInterval(3.0 * 3600 + 58.0 * 60 + 30)
            ),
        ])

        // When: duration only, no percentage
        let label = monitor.menuBarLabel(
            providerId: "claude",
            primaryQuotaKey: "session",
            secondaryQuotaKey: "",
            showPercentage: false,
            showDuration: true,
            mode: .remaining
        )

        // Then
        #expect(label?.text == "3:58")
        #expect(label?.segments == [
            MenuBarLabel.Segment(text: "3:58", status: .healthy),
        ])
    }

    @Test
    func `should give a stacked menu bar each window's percentage and countdown on its own line`() async {
        // Given: both windows carry reset times
        let monitor = await makeRefreshedClaudeMonitor(quotas: [
            UsageQuota(
                percentRemaining: 75,
                quotaType: .session,
                providerId: "claude",
                resetsAt: Date().addingTimeInterval(3.0 * 3600 + 58.0 * 60 + 30)
            ),
            UsageQuota(
                percentRemaining: 35,
                quotaType: .weekly,
                providerId: "claude",
                resetsAt: Date().addingTimeInterval(6.0 * 86400 + 30)
            ),
        ])

        // When: percentage and duration together
        let label = monitor.menuBarLabel(
            providerId: "claude",
            primaryQuotaKey: "session",
            secondaryQuotaKey: "weekly",
            showPercentage: true,
            showDuration: true,
            mode: .remaining
        )

        // Then: segments carry the full "percentage · duration" window texts,
        // each with its own per-window status (matching the dual-window test)
        #expect(label?.text == "5h 75% · 3:58 | 7d 35% · 6d")
        #expect(label?.status == .warning)
        #expect(label?.segments == [
            MenuBarLabel.Segment(text: "5h 75% · 3:58", status: .healthy),
            MenuBarLabel.Segment(text: "7d 35% · 6d", status: .warning),
        ])
    }
}
