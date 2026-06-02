import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

@Suite
struct QuotaMonitorTests {
    private struct TestClock: Clock {
        func sleep(for duration: Duration) async throws {}
        func sleep(nanoseconds: UInt64) async throws {}
    }

    private struct SuspendingClock: Clock {
        func sleep(for duration: Duration) async throws {
            // Keep the monitoring loop suspended after its first tick; stopMonitoring()
            // cancels the task and interrupts this long sleep before the test waits.
            try await Task.sleep(nanoseconds: 60_000_000_000)
        }

        func sleep(nanoseconds: UInt64) async throws {
            try await Task.sleep(nanoseconds: nanoseconds)
        }
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

    private func makeMonitor(
        providers: any AIProviderRepository,
        alerter: (any QuotaAlerter)? = nil
    ) -> QuotaMonitor {
        QuotaMonitor(providers: providers, alerter: alerter, clock: TestClock())
    }

    private func makeSuspendingMonitor(
        providers: any AIProviderRepository,
        alerter: (any QuotaAlerter)? = nil
    ) -> QuotaMonitor {
        QuotaMonitor(providers: providers, alerter: alerter, clock: SuspendingClock())
    }


    /// Creates a mock settings repository that returns true for all providers
    private func makeSettingsRepository() -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(mock).isEnabled(forProvider: .any).willReturn(true)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        return mock
    }

    // MARK: - Single Provider Monitoring

    @Test
    func `monitor can refresh a provider by ID`() async throws {
        // Given
        let settings = makeSettingsRepository()
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(UsageSnapshot(
            providerId: "claude",
            quotas: [
                UsageQuota(percentRemaining: 65, quotaType: .session, providerId: "claude"),
                UsageQuota(percentRemaining: 35, quotaType: .weekly, providerId: "claude"),
            ],
            capturedAt: Date()
        ))
        let provider = ClaudeProvider(probe: probe, settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [provider]))

        // When
        await monitor.refresh(providerId: "claude")

        // Then
        #expect(provider.snapshot != nil)
        #expect(provider.snapshot?.quotas.count == 2)
        #expect(provider.snapshot?.quota(for: .session)?.percentRemaining == 65)
    }

    @Test
    func `menu bar percentage display uses selected quota and display mode`() async {
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
        let provider = ClaudeProvider(probe: probe, settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [provider]))

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
    func `menu bar percentage display falls back when quota data is missing`() {
        // Given
        let settings = makeSettingsRepository()
        let provider = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [provider]))

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
    func `menu bar duration display returns compact reset time for selected quota`() async {
        // Given - claude session quota with reset ~3h away
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
                    resetsAt: Date().addingTimeInterval(3.0 * 3600 + 30)
                ),
            ],
            capturedAt: Date()
        ))
        let provider = ClaudeProvider(probe: probe, settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [provider]))

        // When
        await monitor.refresh(providerId: "claude")
        let display = monitor.menuBarDurationDisplay(
            providerId: "claude",
            quotaKey: "session"
        )

        // Then
        #expect(display?.text == "3h")
        #expect(display?.status == .healthy)
    }

    @Test
    func `menu bar duration display is nil when quota data is missing`() {
        // Given
        let settings = makeSettingsRepository()
        let provider = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [provider]))

        // When
        let display = monitor.menuBarDurationDisplay(
            providerId: "claude",
            quotaKey: "session"
        )

        // Then
        #expect(display == nil)
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
        let provider = ClaudeProvider(probe: probe, settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [provider]))
        await monitor.refresh(providerId: "claude")
        return monitor
    }

    @Test
    func `menu bar label shows single window with no prefix when secondary empty`() async {
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
    func `menu bar label shows both windows prefixed by short label`() async {
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
    func `menu bar label ignores secondary equal to primary`() async {
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
    func `menu bar label falls back to single window when secondary quota missing`() async {
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
    func `menu bar label is nil when neither percentage nor duration enabled`() async {
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
    func `monitor skips unavailable providers`() async {
        // Given
        let settings = makeSettingsRepository()
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(false)
        let provider = ClaudeProvider(probe: probe, settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [provider]))

        // When
        await monitor.refreshAll()

        // Then
        #expect(provider.snapshot == nil)
    }

    // MARK: - Multiple Provider Monitoring

    @Test
    func `monitor refreshes all providers concurrently`() async {
        // Given
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

        let settings = makeSettingsRepository()
        let claudeProvider = ClaudeProvider(probe: claudeProbe, settingsRepository: settings)
        let codexProvider = CodexProvider(probe: codexProbe, settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [claudeProvider, codexProvider]))

        // When
        await monitor.refreshAll()

        // Then
        #expect(claudeProvider.snapshot?.quota(for: .session)?.percentRemaining == 70)
        #expect(codexProvider.snapshot?.quota(for: .session)?.percentRemaining == 40)
    }

    @Test
    func `one provider failure does not affect others`() async {
        // Given
        let settings = makeSettingsRepository()
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

        let claudeProvider = ClaudeProvider(probe: claudeProbe, settingsRepository: settings)
        let codexProvider = CodexProvider(probe: codexProbe, settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [claudeProvider, codexProvider]))

        // When
        await monitor.refreshAll()

        // Then
        #expect(claudeProvider.snapshot != nil)
        #expect(codexProvider.snapshot == nil)
        #expect(codexProvider.lastError != nil)
    }

    // MARK: - Refresh Others

    @Test
    func `refreshOthers excludes the specified provider`() async {
        // Given
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
            quotas: [UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "codex")],
            capturedAt: Date()
        ))

        let geminiProbe = MockUsageProbe()
        given(geminiProbe).isAvailable().willReturn(true)
        given(geminiProbe).probe().willReturn(UsageSnapshot(
            providerId: "gemini",
            quotas: [UsageQuota(percentRemaining: 30, quotaType: .session, providerId: "gemini")],
            capturedAt: Date()
        ))

        let settings = makeSettingsRepository()
        let claudeProvider = ClaudeProvider(probe: claudeProbe, settingsRepository: settings)
        let codexProvider = CodexProvider(probe: codexProbe, settingsRepository: settings)
        let geminiProvider = GeminiProvider(probe: geminiProbe, settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [claudeProvider, codexProvider, geminiProvider]))

        // When - refresh all except Claude
        await monitor.refreshOthers(except: "claude")

        // Then - Codex and Gemini loaded, Claude excluded
        #expect(claudeProvider.snapshot == nil)
        #expect(codexProvider.snapshot?.quota(for: .session)?.percentRemaining == 50)
        #expect(geminiProvider.snapshot?.quota(for: .session)?.percentRemaining == 30)
    }

    // MARK: - Provider Access

    @Test
    func `monitor can find provider by ID`() async {
        // Given
        let settings = makeSettingsRepository()
        let probe = MockUsageProbe()
        let provider = ClaudeProvider(probe: probe, settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [provider]))

        // When
        let found = monitor.provider(for: "claude")

        // Then
        #expect(found?.id == "claude")
    }

    @Test
    func `monitor returns nil for unknown provider ID`() async {
        // Given
        let monitor = makeMonitor(providers: AIProviders(providers: []))

        // When
        let found = monitor.provider(for: "unknown")

        // Then
        #expect(found == nil)
    }

    // MARK: - Overall Status

    @Test
    func `monitor calculates overall status from all providers`() async {
        // Given
        let claudeProbe = MockUsageProbe()
        given(claudeProbe).isAvailable().willReturn(true)
        given(claudeProbe).probe().willReturn(UsageSnapshot(
            providerId: "claude",
            quotas: [UsageQuota(percentRemaining: 70, quotaType: .session, providerId: "claude")], // healthy
            capturedAt: Date()
        ))

        let codexProbe = MockUsageProbe()
        given(codexProbe).isAvailable().willReturn(true)
        given(codexProbe).probe().willReturn(UsageSnapshot(
            providerId: "codex",
            quotas: [UsageQuota(percentRemaining: 15, quotaType: .session, providerId: "codex")], // critical
            capturedAt: Date()
        ))

        let settings = makeSettingsRepository()
        let claudeProvider = ClaudeProvider(probe: claudeProbe, settingsRepository: settings)
        let codexProvider = CodexProvider(probe: codexProbe, settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [claudeProvider, codexProvider]))

        await monitor.refreshAll()

        // When
        let overallStatus = monitor.overallStatus

        // Then - worst status (critical) wins
        #expect(overallStatus == .critical)
    }

    // MARK: - Refresh Selected

    @Test
    func `refreshSelected only refreshes the selected provider`() async {
        // Given
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

        let settings = makeSettingsRepository()
        let claudeProvider = ClaudeProvider(probe: claudeProbe, settingsRepository: settings)
        let codexProvider = CodexProvider(probe: codexProbe, settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [claudeProvider, codexProvider]))

        // Selected provider is "claude" by default

        // When
        await monitor.refreshSelected()

        // Then - only Claude refreshed, Codex untouched
        #expect(claudeProvider.snapshot != nil)
        #expect(codexProvider.snapshot == nil)
    }

    @Test
    func `refreshSelected refreshes newly selected provider`() async {
        // Given
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

        let settings = makeSettingsRepository()
        let claudeProvider = ClaudeProvider(probe: claudeProbe, settingsRepository: settings)
        let codexProvider = CodexProvider(probe: codexProbe, settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [claudeProvider, codexProvider]))

        // When - switch to codex then refresh selected
        monitor.selectProvider(id: "codex")
        await monitor.refreshSelected()

        // Then - only Codex refreshed
        #expect(claudeProvider.snapshot == nil)
        #expect(codexProvider.snapshot != nil)
    }

    // MARK: - Continuous Monitoring

    @Test
    func `monitor can start continuous monitoring`() async throws {
        // Given
        let settings = makeSettingsRepository()
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(UsageSnapshot(
            providerId: "claude",
            quotas: [UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "claude")],
            capturedAt: Date()
        ))
        let provider = ClaudeProvider(probe: probe, settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [provider]))

        // When
        let stream = monitor.startMonitoring(interval: .milliseconds(100))
        var events: [MonitoringEvent] = []

        // Collect first 2 events
        for await event in stream.prefix(2) {
            events.append(event)
        }

        monitor.stopMonitoring()

        // Then
        #expect(events.count == 2)
        #expect(events.allSatisfy { event in
            if case .refreshed = event { return true }
            return false
        })
    }

    @Test
    func `background monitoring refreshes configured menu bar provider in percentage mode`() async {
        // Given
        let settings = makeSettingsRepository()
        let claudeProbe = CountingUsageProbe(providerId: "claude")
        let codexProbe = CountingUsageProbe(providerId: "codex")
        let claudeProvider = ClaudeProvider(probe: claudeProbe, settingsRepository: settings)
        let codexProvider = CodexProvider(probe: codexProbe, settingsRepository: settings)
        let monitor = makeSuspendingMonitor(providers: AIProviders(providers: [claudeProvider, codexProvider]))

        // When - App layer passes selected + configured menu bar provider ids in percentage mode.
        let stream = monitor.startMonitoring(
            interval: .seconds(60),
            providerIds: ["claude", "codex"]
        )
        for await _ in stream.prefix(1) {}
        monitor.stopMonitoring()

        // Then
        #expect(await claudeProbe.counter.count() == 1)
        #expect(await codexProbe.counter.count() == 1)
        #expect(claudeProvider.snapshot != nil)
        #expect(codexProvider.snapshot != nil)
    }

    @Test
    func `background monitoring does not duplicate refreshes when selected and menu bar provider match`() async {
        // Given
        let settings = makeSettingsRepository()
        let probe = CountingUsageProbe(providerId: "claude")
        let provider = ClaudeProvider(probe: probe, settingsRepository: settings)
        let monitor = makeSuspendingMonitor(providers: AIProviders(providers: [provider]))

        // When
        let stream = monitor.startMonitoring(
            interval: .seconds(60),
            providerIds: ["claude", "claude"]
        )
        for await _ in stream.prefix(1) {}
        monitor.stopMonitoring()

        // Then
        #expect(await probe.counter.count() == 1)
    }

    @Test
    func `background monitoring without provider ids preserves selected provider refresh behaviour`() async {
        // Given
        let settings = makeSettingsRepository()
        let claudeProbe = CountingUsageProbe(providerId: "claude")
        let codexProbe = CountingUsageProbe(providerId: "codex")
        let claudeProvider = ClaudeProvider(probe: claudeProbe, settingsRepository: settings)
        let codexProvider = CodexProvider(probe: codexProbe, settingsRepository: settings)
        let monitor = makeSuspendingMonitor(providers: AIProviders(providers: [claudeProvider, codexProvider]))
        monitor.selectProvider(id: "codex")

        // When - icon mode uses the default selected-provider monitoring path.
        let stream = monitor.startMonitoring(interval: .seconds(60))
        for await _ in stream.prefix(1) {}
        monitor.stopMonitoring()

        // Then
        #expect(await claudeProbe.counter.count() == 0)
        #expect(await codexProbe.counter.count() == 1)
    }

    @Test
    func `monitor stops when requested`() async throws {
        // Given
        let settings = makeSettingsRepository()
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(UsageSnapshot(
            providerId: "claude",
            quotas: [UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "claude")],
            capturedAt: Date()
        ))
        let provider = ClaudeProvider(probe: probe, settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [provider]))

        // When
        let stream = monitor.startMonitoring(interval: .milliseconds(50))
        monitor.stopMonitoring()

        var eventCount = 0
        for await _ in stream {
            eventCount += 1
        }

        // Then - Stream should finish quickly after stop
        #expect(eventCount <= 2)
    }

    // MARK: - Provider Collections

    @Test
    func `allProviders returns all registered providers`() {
        // Given
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [claude, codex]))

        // Then
        #expect(monitor.allProviders.count == 2)
    }

    @Test
    func `enabledProviders returns only enabled providers`() {
        // Given
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
        codex.isEnabled = false
        let monitor = makeMonitor(providers: AIProviders(providers: [claude, codex]))

        // Then
        #expect(monitor.enabledProviders.count == 1)
        #expect(monitor.enabledProviders.first?.id == "claude")
    }

    // MARK: - Dynamic Provider Management

    @Test
    func `addProvider adds new provider`() {
        // Given
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [claude]))

        #expect(monitor.allProviders.count == 1)

        // When
        let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
        monitor.addProvider(codex)

        // Then
        #expect(monitor.allProviders.count == 2)
        #expect(monitor.provider(for: "codex") != nil)
    }

    @Test
    func `removeProvider removes provider by id`() {
        // Given
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [claude, codex]))

        #expect(monitor.allProviders.count == 2)

        // When
        monitor.removeProvider(id: "codex")

        // Then
        #expect(monitor.allProviders.count == 1)
        #expect(monitor.provider(for: "codex") == nil)
    }

    // MARK: - Lowest Quota

    @Test
    func `lowestQuota returns lowest across all providers`() async {
        // Given
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
            quotas: [UsageQuota(percentRemaining: 25, quotaType: .session, providerId: "codex")],
            capturedAt: Date()
        ))

        let settings = makeSettingsRepository()
        let claudeProvider = ClaudeProvider(probe: claudeProbe, settingsRepository: settings)
        let codexProvider = CodexProvider(probe: codexProbe, settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [claudeProvider, codexProvider]))

        await monitor.refreshAll()

        // When
        let lowest = monitor.lowestQuota()

        // Then
        #expect(lowest?.percentRemaining == 25)
    }

    @Test
    func `lowestQuota returns nil when no snapshots`() {
        // Given
        let settings = makeSettingsRepository()
        let monitor = makeMonitor(providers: AIProviders(providers: [ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)]))

        // Then
        #expect(monitor.lowestQuota() == nil)
    }

    // MARK: - Selection

    @Test
    func `selectedProvider returns provider matching selectedProviderId`() {
        // Given
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [claude, codex]))

        // When
        monitor.selectedProviderId = "codex"

        // Then
        #expect(monitor.selectedProvider?.id == "codex")
    }

    @Test
    func `selectedProvider returns nil when selected provider is disabled`() {
        // Given
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        claude.isEnabled = false
        let monitor = makeMonitor(providers: AIProviders(providers: [claude]))
        monitor.selectedProviderId = "claude"

        // Then
        #expect(monitor.selectedProvider == nil)
    }

    @Test
    func `selectedProviderStatus returns healthy when no snapshot`() {
        // Given
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [claude]))

        // Then
        #expect(monitor.selectedProviderStatus == .healthy)
    }

    @Test
    func `selectedProviderStatus returns provider status when snapshot exists`() async {
        // Given
        let settings = makeSettingsRepository()
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(UsageSnapshot(
            providerId: "claude",
            quotas: [UsageQuota(percentRemaining: 15, quotaType: .session, providerId: "claude")],
            capturedAt: Date()
        ))
        let claude = ClaudeProvider(probe: probe, settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [claude]))

        await monitor.refresh(providerId: "claude")

        // Then
        #expect(monitor.selectedProviderStatus == .critical)
    }

    @Test
    func `selectProvider updates selectedProviderId for enabled provider`() {
        // Given
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [claude, codex]))

        #expect(monitor.selectedProviderId == "claude")

        // When
        monitor.selectProvider(id: "codex")

        // Then
        #expect(monitor.selectedProviderId == "codex")
    }

    @Test
    func `selectProvider ignores disabled provider`() {
        // Given
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
        codex.isEnabled = false
        let monitor = makeMonitor(providers: AIProviders(providers: [claude, codex]))

        // When
        monitor.selectProvider(id: "codex")

        // Then - still claude because codex is disabled
        #expect(monitor.selectedProviderId == "claude")
    }

    @Test
    func `init selects first enabled when default claude is disabled`() {
        // Given - claude (default) is disabled before init
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
        claude.isEnabled = false

        // When
        let monitor = makeMonitor(providers: AIProviders(providers: [claude, codex]))

        // Then - automatically selects codex (first enabled)
        #expect(monitor.selectedProviderId == "codex")
    }

    @Test
    func `init keeps claude when enabled`() {
        // Given
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)

        // When
        let monitor = makeMonitor(providers: AIProviders(providers: [claude, codex]))

        // Then - keeps default claude
        #expect(monitor.selectedProviderId == "claude")
    }

    // MARK: - Refreshing State

    @Test
    func `isRefreshing returns false when no providers syncing`() {
        // Given
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [claude]))

        // Then
        #expect(monitor.isRefreshing == false)
    }

    // MARK: - AIProviders Repository Init

    @Test
    func `init with AIProviders repository works`() {
        // Given
        let settings = makeSettingsRepository()
        let repository = AIProviders(providers: [
            ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings),
            CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
        ])

        // When
        let monitor = makeMonitor(providers: repository)

        // Then
        #expect(monitor.allProviders.count == 2)
    }

    // MARK: - Quota Alerter

    @Test
    func `alerter is called on status change`() async {
        // Given
        let mockAlerter = MockQuotaAlerter()
        given(mockAlerter).alert(providerId: .any, previousStatus: .any, currentStatus: .any).willReturn(())

        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(UsageSnapshot(
            providerId: "claude",
            quotas: [UsageQuota(percentRemaining: 15, quotaType: .session, providerId: "claude")],
            capturedAt: Date()
        ))
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: probe, settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [claude]), alerter: mockAlerter)

        // When
        await monitor.refresh(providerId: "claude")

        // Then
        verify(mockAlerter).alert(
            providerId: .value("claude"),
            previousStatus: .value(.healthy),
            currentStatus: .value(.critical)
        ).called(1)
    }

    @Test
    func `alerter not called when status unchanged`() async {
        // Given
        let mockAlerter = MockQuotaAlerter()
        given(mockAlerter).alert(providerId: .any, previousStatus: .any, currentStatus: .any).willReturn(())

        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(UsageSnapshot(
            providerId: "claude",
            quotas: [UsageQuota(percentRemaining: 70, quotaType: .session, providerId: "claude")],
            capturedAt: Date()
        ))
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: probe, settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [claude]), alerter: mockAlerter)

        // When - refresh twice with same status
        await monitor.refresh(providerId: "claude")
        await monitor.refresh(providerId: "claude")

        // Then - only notified once (first change from nil/healthy to healthy)
        // Actually, the first refresh won't trigger because healthy -> healthy
        verify(mockAlerter).alert(providerId: .any, previousStatus: .any, currentStatus: .any).called(0)
    }

    // MARK: - Disabled Provider Skipping

    @Test
    func `refreshAll skips disabled providers`() async {
        // Given
        let claudeProbe = MockUsageProbe()
        given(claudeProbe).isAvailable().willReturn(true)
        given(claudeProbe).probe().willReturn(UsageSnapshot(
            providerId: "claude",
            quotas: [UsageQuota(percentRemaining: 70, quotaType: .session, providerId: "claude")],
            capturedAt: Date()
        ))

        let codexProbe = MockUsageProbe()
        // Don't set up codex probe expectations - it shouldn't be called

        let settings = makeSettingsRepository()
        let claudeProvider = ClaudeProvider(probe: claudeProbe, settingsRepository: settings)
        let codexProvider = CodexProvider(probe: codexProbe, settingsRepository: settings)
        codexProvider.isEnabled = false

        let monitor = makeMonitor(providers: AIProviders(providers: [claudeProvider, codexProvider]))

        // When
        await monitor.refreshAll()

        // Then - claude refreshed, codex skipped (no snapshot)
        #expect(claudeProvider.snapshot != nil)
        #expect(codexProvider.snapshot == nil)
    }

    @Test
    func `overallStatus only considers enabled providers`() async {
        // Given
        let claudeProbe = MockUsageProbe()
        given(claudeProbe).isAvailable().willReturn(true)
        given(claudeProbe).probe().willReturn(UsageSnapshot(
            providerId: "claude",
            quotas: [UsageQuota(percentRemaining: 70, quotaType: .session, providerId: "claude")], // healthy
            capturedAt: Date()
        ))

        let codexProbe = MockUsageProbe()
        given(codexProbe).isAvailable().willReturn(true)
        given(codexProbe).probe().willReturn(UsageSnapshot(
            providerId: "codex",
            quotas: [UsageQuota(percentRemaining: 5, quotaType: .session, providerId: "codex")], // critical
            capturedAt: Date()
        ))

        let settings = makeSettingsRepository()
        let claudeProvider = ClaudeProvider(probe: claudeProbe, settingsRepository: settings)
        let codexProvider = CodexProvider(probe: codexProbe, settingsRepository: settings)

        let monitor = makeMonitor(providers: AIProviders(providers: [claudeProvider, codexProvider]))

        // First refresh both
        await monitor.refreshAll()
        #expect(monitor.overallStatus == .critical)

        // Disable codex
        codexProvider.isEnabled = false

        // Then - only claude's healthy status matters
        #expect(monitor.overallStatus == .healthy)
    }

    // MARK: - Set Provider Enabled

    @Test
    func `setProviderEnabled disables provider and updates selection`() {
        // Given
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [claude, codex]))
        monitor.selectedProviderId = "claude"

        // When - disable the currently selected provider
        monitor.setProviderEnabled("claude", enabled: false)

        // Then - provider is disabled and selection switches to first enabled
        #expect(claude.isEnabled == false)
        #expect(monitor.selectedProviderId == "codex")
    }

    @Test
    func `setProviderEnabled enables provider without changing selection`() {
        // Given
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
        codex.isEnabled = false
        let monitor = makeMonitor(providers: AIProviders(providers: [claude, codex]))
        monitor.selectedProviderId = "claude"

        // When - enable a different provider
        monitor.setProviderEnabled("codex", enabled: true)

        // Then - provider is enabled, selection unchanged
        #expect(codex.isEnabled == true)
        #expect(monitor.selectedProviderId == "claude")
    }
}
