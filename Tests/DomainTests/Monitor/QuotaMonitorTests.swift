import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

@Suite
@MainActor
struct QuotaMonitorTests {
    private struct TestClock: Clock {
        func sleep(for duration: Duration) async throws {}
        func sleep(nanoseconds: UInt64) async throws {}
    }

    /// A clock whose `sleep` suspends until the surrounding task is cancelled,
    /// rather than waiting real wall-clock time. The monitoring loop runs exactly
    /// one cycle and then parks here; `stopMonitoring()` (or stream termination)
    /// cancels the loop's task, resuming this with a `CancellationError` so the
    /// loop ends at once. Replacing the old real `Task.sleep(60s)` removes the
    /// timing race that made the continuous-monitoring tests flake under load.
    private final class SuspendingClock: Clock, @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, Error>?
        private var cancelled = false

        /// Parks the caller on a continuation that only resumes — throwing
        /// `CancellationError` — once the surrounding task is cancelled, so the
        /// monitoring loop suspends after one cycle instead of sleeping for real.
        func sleep(for duration: Duration) async throws {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    lock.lock()
                    if cancelled {
                        lock.unlock()
                        cont.resume(throwing: CancellationError())
                    } else {
                        continuation = cont
                        lock.unlock()
                    }
                }
            } onCancel: {
                lock.lock()
                cancelled = true
                let cont = continuation
                continuation = nil
                lock.unlock()
                cont?.resume(throwing: CancellationError())
            }
        }

        /// Bridges the legacy nanosecond API onto the cancellation-gated `sleep(for:)`.
        func sleep(nanoseconds: UInt64) async throws {
            try await sleep(for: .nanoseconds(Int64(nanoseconds)))
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
        let provider = StubClaudeProvider(probe: probe, settingsRepository: settings)
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
        let provider = StubClaudeProvider(probe: probe, settingsRepository: settings)
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
        let provider = StubClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
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
        let provider = StubClaudeProvider(probe: probe, settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [provider]))

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
    func `menu bar duration display is nil when quota data is missing`() {
        // Given
        let settings = makeSettingsRepository()
        let provider = StubClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [provider]))

        // When
        let display = monitor.menuBarDurationDisplay(
            providerId: "claude",
            quotaKey: "session"
        )

        // Then
        #expect(display == nil)
    }

    @Test
    func `additional menu bar labels use first quota and identify provider`() async {
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
    func `additional labels keep selection order and omit disabled providers`() async {
        let settings = makeSettingsRepository()
        let claude = StubClaudeProvider(probe: CountingUsageProbe(providerId: "claude"), settingsRepository: settings)
        let codex = StubCodexProvider(probe: CountingUsageProbe(providerId: "codex"), settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [claude, codex]))
        await monitor.refresh(providerId: "claude")
        await monitor.refresh(providerId: "codex")
        #expect(monitor.additionalMenuBarLabels(
            providerIds: ["codex", "codex", "claude"], showPercentage: true,
            showDuration: false, mode: .used
        ).map(\.text) == ["Codex 1%", "Claude 1%"])
        codex.isEnabled = false
        #expect(monitor.additionalMenuBarLabels(
            providerIds: ["codex", "claude"], showPercentage: true,
            showDuration: false, mode: .remaining
        ).map(\.text) == ["Claude 99%"])
    }

    @Test
    func `additional provider awaiting first snapshot has a named placeholder`() {
        let provider = StubClaudeProvider(
            probe: CountingUsageProbe(providerId: "claude"), settingsRepository: makeSettingsRepository()
        )
        let monitor = makeMonitor(providers: AIProviders(providers: [provider]))
        #expect(monitor.additionalMenuBarLabels(
            providerIds: ["claude"], showPercentage: true, showDuration: false, mode: .remaining
        ).map(\.text) == ["Claude —"])
    }

    @Test
    func `additional providers honor their own primary secondary and stacked choices`() async {
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
        let provider = StubClaudeProvider(probe: probe, settingsRepository: settings)
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
    func `menu bar label carries a single segment when secondary empty`() async {
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
    func `menu bar label carries both windows as separate segments`() async {
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
    func `menu bar label prefers the quota's menuBarTitle for window prefixes`() async {
        // Given: an aggregated quota whose full label carries a long account
        // discriminator, condensed by the probe into `menuBarTitle`; the
        // weekly window carries no override
        let monitor = await makeRefreshedClaudeMonitor(quotas: [
            UsageQuota(
                percentRemaining: 69,
                quotaType: .timeLimit("Claude 7d · jkjk987654321012"),
                providerId: "claude",
                menuBarTitle: "Claude 7d · jkjk987…"
            ),
            UsageQuota(percentRemaining: 35, quotaType: .weekly, providerId: "claude"),
        ])

        // When
        let label = monitor.menuBarLabel(
            providerId: "claude",
            primaryQuotaKey: "time:Claude 7d · jkjk987654321012",
            secondaryQuotaKey: "weekly",
            showPercentage: true,
            showDuration: false,
            mode: .remaining
        )

        // Then: the condensed title replaces the full label in the joined
        // text and the segment; windows without an override keep shortLabel
        #expect(label?.text == "Claude 7d · jkjk987… 69% | 7d 35%")
        #expect(label?.segments == [
            MenuBarLabel.Segment(text: "Claude 7d · jkjk987… 69%", status: .healthy),
            MenuBarLabel.Segment(text: "7d 35%", status: .warning),
        ])
    }

    @Test
    func `menu bar label segments cover the duration-only variant`() async {
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
    func `menu bar label segments cover percentage plus duration windows`() async {
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

    @Test
    func `monitor skips unavailable providers`() async {
        // Given
        let settings = makeSettingsRepository()
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(false)
        let provider = StubClaudeProvider(probe: probe, settingsRepository: settings)
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
        let claudeProvider = StubClaudeProvider(probe: claudeProbe, settingsRepository: settings)
        let codexProvider = StubCodexProvider(probe: codexProbe, settingsRepository: settings)
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
        given(codexProbe).probe().willThrow(UsageError.timeout)

        let claudeProvider = StubClaudeProvider(probe: claudeProbe, settingsRepository: settings)
        let codexProvider = StubCodexProvider(probe: codexProbe, settingsRepository: settings)
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
        let claudeProvider = StubClaudeProvider(probe: claudeProbe, settingsRepository: settings)
        let codexProvider = StubCodexProvider(probe: codexProbe, settingsRepository: settings)
        let geminiProvider = StubGeminiProvider(probe: geminiProbe, settingsRepository: settings)
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
        let provider = StubClaudeProvider(probe: probe, settingsRepository: settings)
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
        let claudeProvider = StubClaudeProvider(probe: claudeProbe, settingsRepository: settings)
        let codexProvider = StubCodexProvider(probe: codexProbe, settingsRepository: settings)
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
        let claudeProvider = StubClaudeProvider(probe: claudeProbe, settingsRepository: settings)
        let codexProvider = StubCodexProvider(probe: codexProbe, settingsRepository: settings)
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
        let claudeProvider = StubClaudeProvider(probe: claudeProbe, settingsRepository: settings)
        let codexProvider = StubCodexProvider(probe: codexProbe, settingsRepository: settings)
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
        let provider = StubClaudeProvider(probe: probe, settingsRepository: settings)
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
        let claudeProvider = StubClaudeProvider(probe: claudeProbe, settingsRepository: settings)
        let codexProvider = StubCodexProvider(probe: codexProbe, settingsRepository: settings)
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
        let provider = StubClaudeProvider(probe: probe, settingsRepository: settings)
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
        let claudeProvider = StubClaudeProvider(probe: claudeProbe, settingsRepository: settings)
        let codexProvider = StubCodexProvider(probe: codexProbe, settingsRepository: settings)
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
        let provider = StubClaudeProvider(probe: probe, settingsRepository: settings)
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

    /// #182 regression guard: monitoring flips `isMonitoring` on at start and
    /// off at stop entirely on the main actor (this @MainActor suite would not
    /// compile otherwise), so observable state is never mutated off-main.
    @Test
    func `startMonitoring keeps observable state on the main actor`() async {
        // Reading and writing isMonitoring here compiles only because both this
        // suite and QuotaMonitor are @MainActor — the structural guard against
        // the #182 off-main mutation. The flow asserts the flag flips on, then off.
        let settings = makeSettingsRepository()
        let provider = StubClaudeProvider(probe: CountingUsageProbe(providerId: "claude"), settingsRepository: settings)
        let monitor = makeSuspendingMonitor(providers: AIProviders(providers: [provider]))

        let stream = monitor.startMonitoring(interval: .seconds(60))
        #expect(monitor.isMonitoring == true)

        for await _ in stream.prefix(1) {}
        monitor.stopMonitoring()

        #expect(monitor.isMonitoring == false)
    }

    /// Sub-minute and zero intervals clamp up to the 1-minute floor, while
    /// at- or above-floor intervals pass through unchanged (energy — #67).
    @Test
    func `clampedInterval enforces the one minute floor`() {
        #expect(QuotaMonitor.clampedInterval(.seconds(5)) == .seconds(60))
        #expect(QuotaMonitor.clampedInterval(.zero) == .seconds(60))
        #expect(QuotaMonitor.clampedInterval(.seconds(60)) == .seconds(60))
        #expect(QuotaMonitor.clampedInterval(.seconds(300)) == .seconds(300))
        #expect(QuotaMonitor.clampedInterval(.seconds(900)) == .seconds(900))
    }

    /// The background cadence is the requested interval clamped to the 1-minute
    /// floor, then raised to the slowest provider-imposed floor in the active set
    /// (Claude API → 15 min — issue #204).
    @Test
    func `effectiveInterval clamps then raises to the slowest provider floor`() {
        // No provider floor → clamped requested.
        #expect(QuotaMonitor.effectiveInterval(requested: .seconds(600), floors: []) == .seconds(600))
        #expect(QuotaMonitor.effectiveInterval(requested: .seconds(5), floors: []) == .seconds(60))
        // A floor below the requested cadence leaves it unchanged.
        #expect(QuotaMonitor.effectiveInterval(requested: .seconds(600), floors: [.seconds(60)]) == .seconds(600))
        // The Claude API floor lifts even the 1-minute option to 15 minutes.
        #expect(QuotaMonitor.effectiveInterval(requested: .seconds(60), floors: [.seconds(900)]) == .seconds(900))
        #expect(QuotaMonitor.effectiveInterval(requested: .seconds(600), floors: [.seconds(900)]) == .seconds(900))
        // The slowest floor wins for a mixed set.
        #expect(QuotaMonitor.effectiveInterval(requested: .seconds(60), floors: [.seconds(300), .seconds(900)]) == .seconds(900))
    }

    // MARK: - Energy Awareness (issue #204)

    /// A controllable `PowerStateProvider` fake. `waitUntilParked()` lets a test
    /// deterministically know the monitoring loop has reached the asleep gate
    /// (and is about to park on the event stream), so a "no refresh while asleep"
    /// assertion is race-free.
    private final class FakePowerStateProvider: PowerStateProvider, @unchecked Sendable {
        private let lock = NSLock()
        private var asleep: Bool
        private var battery: Bool
        private var continuation: AsyncStream<PowerEvent>.Continuation?
        private var asleepChecks = 0
        private var awaitingCheck: CheckedContinuation<Void, Never>?

        init(asleep: Bool = false, onBattery: Bool = false) {
            self.asleep = asleep
            self.battery = onBattery
        }

        var isDisplayAsleep: Bool {
            lock.lock()
            let value = asleep
            var signal: CheckedContinuation<Void, Never>?
            if value {
                asleepChecks += 1
                signal = awaitingCheck
                awaitingCheck = nil
            }
            lock.unlock()
            signal?.resume()
            return value
        }

        var isOnBattery: Bool {
            lock.lock(); defer { lock.unlock() }
            return battery
        }

        func events() -> AsyncStream<PowerEvent> {
            AsyncStream { continuation in
                self.lock.lock()
                self.continuation = continuation
                self.lock.unlock()
            }
        }

        /// Resumes once the loop has read `isDisplayAsleep` while asleep.
        func waitUntilParked() async {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                lock.lock()
                if asleepChecks > 0 {
                    lock.unlock()
                    cont.resume()
                } else {
                    awaitingCheck = cont
                    lock.unlock()
                }
            }
        }

        func wake() {
            lock.lock()
            asleep = false
            let cont = continuation
            lock.unlock()
            cont?.yield(.didWake)
        }
    }

    /// A clock that records each requested sleep duration, then ends the loop by
    /// throwing — so a single monitoring tick runs deterministically and the
    /// recorded cadence can be asserted.
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

    @Test
    func `background loop pauses while display asleep and refreshes on wake`() async {
        let settings = makeSettingsRepository()
        let probe = CountingUsageProbe(providerId: "claude")
        let provider = StubClaudeProvider(probe: probe, settingsRepository: settings)
        let power = FakePowerStateProvider(asleep: true)
        let monitor = QuotaMonitor(
            providers: AIProviders(providers: [provider]),
            clock: RecordingClock(),
            powerStateProvider: power
        )

        let stream = monitor.startMonitoring(interval: .seconds(60))

        // The loop reaches the asleep gate and parks — no refresh while asleep.
        await power.waitUntilParked()
        #expect(await probe.counter.count() == 0)

        // Waking lets exactly one refresh through, then the clock ends the loop.
        power.wake()
        for await _ in stream {}
        #expect(await probe.counter.count() == 1)
    }

    @Test
    func `background loop doubles the cadence while on battery`() async {
        let settings = makeSettingsRepository()
        let provider = StubClaudeProvider(probe: CountingUsageProbe(providerId: "claude"), settingsRepository: settings)
        let power = FakePowerStateProvider(asleep: false, onBattery: true)
        let clock = RecordingClock()
        let monitor = QuotaMonitor(
            providers: AIProviders(providers: [provider]),
            clock: clock,
            powerStateProvider: power
        )

        let stream = monitor.startMonitoring(interval: .seconds(600))
        for await _ in stream {}

        // 600s → 1200s on battery (×2); CLI mode adds no provider floor.
        #expect(clock.durations == [.seconds(1200)])
    }

    @Test
    func `background loop keeps the normal cadence on AC power`() async {
        let settings = makeSettingsRepository()
        let provider = StubClaudeProvider(probe: CountingUsageProbe(providerId: "claude"), settingsRepository: settings)
        let power = FakePowerStateProvider(asleep: false, onBattery: false)
        let clock = RecordingClock()
        let monitor = QuotaMonitor(
            providers: AIProviders(providers: [provider]),
            clock: clock,
            powerStateProvider: power
        )

        let stream = monitor.startMonitoring(interval: .seconds(600))
        for await _ in stream {}

        #expect(clock.durations == [.seconds(600)])
    }

    // MARK: - Provider Collections

    @Test
    func `allProviders returns all registered providers`() {
        // Given
        let settings = makeSettingsRepository()
        let claude = StubClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let codex = StubCodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [claude, codex]))

        // Then
        #expect(monitor.allProviders.count == 2)
    }

    @Test
    func `enabledProviders returns only enabled providers`() {
        // Given
        let settings = makeSettingsRepository()
        let claude = StubClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let codex = StubCodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
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
        let claude = StubClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [claude]))

        #expect(monitor.allProviders.count == 1)

        // When
        let codex = StubCodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
        monitor.addProvider(codex)

        // Then
        #expect(monitor.allProviders.count == 2)
        #expect(monitor.provider(for: "codex") != nil)
    }

    @Test
    func `removeProvider removes provider by id`() {
        // Given
        let settings = makeSettingsRepository()
        let claude = StubClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let codex = StubCodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
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
        let claudeProvider = StubClaudeProvider(probe: claudeProbe, settingsRepository: settings)
        let codexProvider = StubCodexProvider(probe: codexProbe, settingsRepository: settings)
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
        let monitor = makeMonitor(providers: AIProviders(providers: [StubClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)]))

        // Then
        #expect(monitor.lowestQuota() == nil)
    }

    // MARK: - Selection

    @Test
    func `selectedProvider returns provider matching selectedProviderId`() {
        // Given
        let settings = makeSettingsRepository()
        let claude = StubClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let codex = StubCodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
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
        let claude = StubClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
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
        let claude = StubClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
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
        let claude = StubClaudeProvider(probe: probe, settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [claude]))

        await monitor.refresh(providerId: "claude")

        // Then
        #expect(monitor.selectedProviderStatus == .critical)
    }

    @Test
    func `selectProvider updates selectedProviderId for enabled provider`() {
        // Given
        let settings = makeSettingsRepository()
        let claude = StubClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let codex = StubCodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
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
        let claude = StubClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let codex = StubCodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
        codex.isEnabled = false
        let monitor = makeMonitor(providers: AIProviders(providers: [claude, codex]))

        // When
        monitor.selectProvider(id: "codex")

        // Then - still claude because codex is disabled
        #expect(monitor.selectedProviderId == "claude")
    }

    @Test
    func `selectProvider at position selects the enabled provider shown in that slot`() {
        // Given - gemini sits between two enabled providers but is disabled,
        // so the pills read: 1 Claude, 2 Codex
        let settings = makeSettingsRepository()
        let claude = StubClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let gemini = StubGeminiProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let codex = StubCodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
        gemini.isEnabled = false
        let monitor = makeMonitor(providers: AIProviders(providers: [claude, gemini, codex]))

        // When
        monitor.selectProvider(atPosition: 2)

        // Then
        #expect(monitor.selectedProviderId == "codex")
    }

    @Test
    func `selectProvider at position ignores a slot with no provider`() {
        // Given
        let settings = makeSettingsRepository()
        let claude = StubClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let codex = StubCodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [claude, codex]))

        // When
        monitor.selectProvider(atPosition: 3)
        monitor.selectProvider(atPosition: 0)

        // Then
        #expect(monitor.selectedProviderId == "claude")
    }

    @Test
    func `init selects first enabled when default claude is disabled`() {
        // Given - claude (default) is disabled before init
        let settings = makeSettingsRepository()
        let claude = StubClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let codex = StubCodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
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
        let claude = StubClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let codex = StubCodexProvider(probe: MockUsageProbe(), settingsRepository: settings)

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
        let claude = StubClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
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
            StubClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings),
            StubCodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
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
        let claude = StubClaudeProvider(probe: probe, settingsRepository: settings)
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
        let claude = StubClaudeProvider(probe: probe, settingsRepository: settings)
        let monitor = makeMonitor(providers: AIProviders(providers: [claude]), alerter: mockAlerter)

        // When - refresh twice with same status
        await monitor.refresh(providerId: "claude")
        await monitor.refresh(providerId: "claude")

        // Then - only notified once (first change from nil/healthy to healthy)
        // Actually, the first refresh won't trigger because healthy -> healthy
        verify(mockAlerter).alert(providerId: .any, previousStatus: .any, currentStatus: .any).called(0)
    }

    @Test
    func `with pace-aware status an on-pace quota raises no warning`() async {
        // Given — 40% left with 90% of the window gone: on pace, so healthy
        let mockAlerter = MockQuotaAlerter()
        given(mockAlerter).alert(providerId: .any, previousStatus: .any, currentStatus: .any).willReturn(())
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(UsageSnapshot(
            providerId: "claude",
            quotas: [UsageQuota(
                percentRemaining: 40, quotaType: .session, providerId: "claude",
                resetsAt: Date().addingTimeInterval(30 * 60), windowDuration: 5 * 3600
            )],
            capturedAt: Date()
        ))
        let claude = StubClaudeProvider(probe: probe, settingsRepository: makeSettingsRepository())
        let monitor = QuotaMonitor(
            providers: AIProviders(providers: [claude]), alerter: mockAlerter, clock: TestClock(),
            statusPolicy: { .paceAware(burnRateThreshold: 1.5) }
        )

        // When
        await monitor.refresh(providerId: "claude")

        // Then — the notification agrees with the menu bar: no warning
        verify(mockAlerter).alert(providerId: .any, previousStatus: .any, currentStatus: .any).called(0)
        #expect(monitor.selectedProviderStatus == .healthy)
    }

    @Test
    func `with absolute status the same quota warns`() async {
        let mockAlerter = MockQuotaAlerter()
        given(mockAlerter).alert(providerId: .any, previousStatus: .any, currentStatus: .any).willReturn(())
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(UsageSnapshot(
            providerId: "claude",
            quotas: [UsageQuota(
                percentRemaining: 40, quotaType: .session, providerId: "claude",
                resetsAt: Date().addingTimeInterval(30 * 60), windowDuration: 5 * 3600
            )],
            capturedAt: Date()
        ))
        let claude = StubClaudeProvider(probe: probe, settingsRepository: makeSettingsRepository())
        let monitor = QuotaMonitor(
            providers: AIProviders(providers: [claude]), alerter: mockAlerter, clock: TestClock(),
            statusPolicy: { .absolute }
        )

        await monitor.refresh(providerId: "claude")

        verify(mockAlerter).alert(
            providerId: .value("claude"), previousStatus: .value(.healthy), currentStatus: .value(.warning)
        ).called(1)
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
        let claudeProvider = StubClaudeProvider(probe: claudeProbe, settingsRepository: settings)
        let codexProvider = StubCodexProvider(probe: codexProbe, settingsRepository: settings)
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
        let claudeProvider = StubClaudeProvider(probe: claudeProbe, settingsRepository: settings)
        let codexProvider = StubCodexProvider(probe: codexProbe, settingsRepository: settings)

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
        let claude = StubClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let codex = StubCodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
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
        let claude = StubClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let codex = StubCodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
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
