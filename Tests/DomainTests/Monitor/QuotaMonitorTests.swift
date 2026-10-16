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
        providers: Providers,
        alerter: (any QuotaAlerter)? = nil
    ) -> QuotaMonitor {
        QuotaMonitor(providers: providers, alerter: alerter, clock: TestClock())
    }

    private func makeSuspendingMonitor(
        providers: Providers,
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

    // MARK: - After a refresh: the one extension point

    @Test
    func `should tell every listener, in turn, about each login that refreshed`() async throws {
        let settings = makeSettingsRepository()
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(UsageSnapshot(providerId: "claude", quotas: [], capturedAt: Date()))
        let providerProduct = stubbedProduct("claude", probe: probe, settings: settings)
        let provider = providerProduct.defaultAccount
        let monitor = makeMonitor(providers: kept([providerProduct]))
        var heard: [String] = []
        monitor.onRefreshed { heard.append("first:\($0.id)") }
        monitor.onRefreshed { heard.append("second:\($0.id)") }

        await monitor.refresh(providerId: "claude")

        #expect(heard == ["first:claude", "second:claude"])
    }

    @Test
    func `should tell no listener when the login's refresh fails`() async throws {
        let settings = makeSettingsRepository()
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willThrow(UsageError.timeout)
        let providerProduct = stubbedProduct("claude", probe: probe, settings: settings)
        let provider = providerProduct.defaultAccount
        let monitor = makeMonitor(providers: kept([providerProduct]))
        var heard = 0
        monitor.onRefreshed { _ in heard += 1 }

        await monitor.refresh(providerId: "claude")

        #expect(heard == 0)
    }

    @Test
    func `should show a provider's session and weekly quotas after refreshing it`() async throws {
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
        let providerProduct = stubbedProduct("claude", probe: probe, settings: settings)
        let provider = providerProduct.defaultAccount
        let monitor = makeMonitor(providers: kept([providerProduct]))

        // When
        await monitor.refresh(providerId: "claude")

        // Then
        #expect(provider.snapshot != nil)
        #expect(provider.snapshot?.quotas.count == 2)
        #expect(provider.snapshot?.quota(for: .session)?.percentRemaining == 65)
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

    @Test
    func `should show no quotas for a provider that is not available`() async {
        // Given
        let settings = makeSettingsRepository()
        let probe = MockUsageProbe()
        let providerProduct = stubbedProduct("claude", probe: probe, settings: settings, available: false)
        let provider = providerProduct.defaultAccount
        let monitor = makeMonitor(providers: kept([providerProduct]))

        // When
        await monitor.refreshAll()

        // Then
        #expect(provider.snapshot == nil)
    }

    // MARK: - Multiple Provider Monitoring

    @Test
    func `should show every provider's quotas after refreshing all`() async {
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
        let claudeProviderProduct = stubbedProduct("claude", probe: claudeProbe, settings: settings)
        let claudeProvider = claudeProviderProduct.defaultAccount
        let codexProviderProduct = stubbedProduct("codex", probe: codexProbe, settings: settings)
        let codexProvider = codexProviderProduct.defaultAccount
        let monitor = makeMonitor(providers: kept([claudeProviderProduct, codexProviderProduct]))

        // When
        await monitor.refreshAll()

        // Then
        #expect(claudeProvider.snapshot?.quota(for: .session)?.percentRemaining == 70)
        #expect(codexProvider.snapshot?.quota(for: .session)?.percentRemaining == 40)
    }

    @Test
    func `should still show the other providers' quotas when one provider fails`() async {
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

        let claudeProviderProduct = stubbedProduct("claude", probe: claudeProbe, settings: settings)
        let claudeProvider = claudeProviderProduct.defaultAccount
        let codexProviderProduct = stubbedProduct("codex", probe: codexProbe, settings: settings)
        let codexProvider = codexProviderProduct.defaultAccount
        let monitor = makeMonitor(providers: kept([claudeProviderProduct, codexProviderProduct]))

        // When
        await monitor.refreshAll()

        // Then
        #expect(claudeProvider.snapshot != nil)
        #expect(codexProvider.snapshot == nil)
        #expect(codexProvider.lastError != nil)
    }

    // MARK: - Refresh Others

    @Test
    func `should refresh every provider but the one just refreshed`() async {
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
        let claudeProviderProduct = stubbedProduct("claude", probe: claudeProbe, settings: settings)
        let claudeProvider = claudeProviderProduct.defaultAccount
        let codexProviderProduct = stubbedProduct("codex", probe: codexProbe, settings: settings)
        let codexProvider = codexProviderProduct.defaultAccount
        let geminiProviderProduct = stubbedProduct("gemini", probe: geminiProbe, settings: settings)
        let geminiProvider = geminiProviderProduct.defaultAccount
        let monitor = makeMonitor(providers: kept([claudeProviderProduct, codexProviderProduct, geminiProviderProduct]))

        // When - refresh all except Claude
        await monitor.refreshOthers(except: "claude")

        // Then - Codex and Gemini loaded, Claude excluded
        #expect(claudeProvider.snapshot == nil)
        #expect(codexProvider.snapshot?.quota(for: .session)?.percentRemaining == 50)
        #expect(geminiProvider.snapshot?.quota(for: .session)?.percentRemaining == 30)
    }

    // MARK: - Provider Access

    @Test
    func `should find a login by its provider's id`() async {
        // Given
        let settings = makeSettingsRepository()
        let probe = MockUsageProbe()
        let providerProduct = stubbedProduct("claude", probe: probe, settings: settings)
        let provider = providerProduct.defaultAccount
        let monitor = makeMonitor(providers: kept([providerProduct]))

        // When
        let found = monitor.login(id: "claude")

        // Then
        #expect(found?.id == "claude")
    }

    @Test
    func `should find no login for an unknown provider id`() async {
        // Given
        let monitor = makeMonitor(providers: kept([]))

        // When
        let found = monitor.login(id: "unknown")

        // Then
        #expect(found == nil)
    }

    // MARK: - Overall Status

    @Test
    func `should take the worst provider's status as the overall status`() async {
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
        let claudeProviderProduct = stubbedProduct("claude", probe: claudeProbe, settings: settings)
        let claudeProvider = claudeProviderProduct.defaultAccount
        let codexProviderProduct = stubbedProduct("codex", probe: codexProbe, settings: settings)
        let codexProvider = codexProviderProduct.defaultAccount
        let monitor = makeMonitor(providers: kept([claudeProviderProduct, codexProviderProduct]))

        await monitor.refreshAll()

        // When
        let overallStatus = monitor.overallStatus

        // Then - worst status (critical) wins
        #expect(overallStatus == .critical)
    }

    // MARK: - Refresh Selected

    @Test
    func `should refresh only the selected provider`() async {
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
        let claudeProviderProduct = stubbedProduct("claude", probe: claudeProbe, settings: settings)
        let claudeProvider = claudeProviderProduct.defaultAccount
        let codexProviderProduct = stubbedProduct("codex", probe: codexProbe, settings: settings)
        let codexProvider = codexProviderProduct.defaultAccount
        let monitor = makeMonitor(providers: kept([claudeProviderProduct, codexProviderProduct]))

        // Selected provider is "claude" by default

        // When
        await monitor.refreshSelected()

        // Then - only Claude refreshed, Codex untouched
        #expect(claudeProvider.snapshot != nil)
        #expect(codexProvider.snapshot == nil)
    }

    @Test
    func `should refresh the provider the person just switched to`() async {
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
        let claudeProviderProduct = stubbedProduct("claude", probe: claudeProbe, settings: settings)
        let claudeProvider = claudeProviderProduct.defaultAccount
        let codexProviderProduct = stubbedProduct("codex", probe: codexProbe, settings: settings)
        let codexProvider = codexProviderProduct.defaultAccount
        let monitor = makeMonitor(providers: kept([claudeProviderProduct, codexProviderProduct]))

        // When - switch to codex then refresh selected
        monitor.selectProvider(id: "codex")
        await monitor.refreshSelected()

        // Then - only Codex refreshed
        #expect(claudeProvider.snapshot == nil)
        #expect(codexProvider.snapshot != nil)
    }

    // MARK: - Continuous Monitoring

    @Test
    func `should report each background refresh while monitoring runs`() async throws {
        // Given
        let settings = makeSettingsRepository()
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(UsageSnapshot(
            providerId: "claude",
            quotas: [UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "claude")],
            capturedAt: Date()
        ))
        let providerProduct = stubbedProduct("claude", probe: probe, settings: settings)
        let provider = providerProduct.defaultAccount
        let monitor = makeMonitor(providers: kept([providerProduct]))

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
    func `should refresh the selected provider and the menu bar's providers in the background`() async {
        // Given
        let settings = makeSettingsRepository()
        let claudeProbe = CountingUsageProbe(providerId: "claude")
        let codexProbe = CountingUsageProbe(providerId: "codex")
        let claudeProviderProduct = stubbedProduct("claude", probe: claudeProbe, settings: settings)
        let claudeProvider = claudeProviderProduct.defaultAccount
        let codexProviderProduct = stubbedProduct("codex", probe: codexProbe, settings: settings)
        let codexProvider = codexProviderProduct.defaultAccount
        let monitor = makeSuspendingMonitor(providers: kept([claudeProviderProduct, codexProviderProduct]))

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
    func `should refresh a provider once in the background when it is both selected and in the menu bar`() async {
        // Given
        let settings = makeSettingsRepository()
        let probe = CountingUsageProbe(providerId: "claude")
        let providerProduct = stubbedProduct("claude", probe: probe, settings: settings)
        let provider = providerProduct.defaultAccount
        let monitor = makeSuspendingMonitor(providers: kept([providerProduct]))

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
    func `should refresh only the selected provider in the background when the menu bar names none`() async {
        // Given
        let settings = makeSettingsRepository()
        let claudeProbe = CountingUsageProbe(providerId: "claude")
        let codexProbe = CountingUsageProbe(providerId: "codex")
        let claudeProviderProduct = stubbedProduct("claude", probe: claudeProbe, settings: settings)
        let claudeProvider = claudeProviderProduct.defaultAccount
        let codexProviderProduct = stubbedProduct("codex", probe: codexProbe, settings: settings)
        let codexProvider = codexProviderProduct.defaultAccount
        let monitor = makeSuspendingMonitor(providers: kept([claudeProviderProduct, codexProviderProduct]))
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
    func `should stop reporting refreshes once monitoring is stopped`() async throws {
        // Given
        let settings = makeSettingsRepository()
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(UsageSnapshot(
            providerId: "claude",
            quotas: [UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "claude")],
            capturedAt: Date()
        ))
        let providerProduct = stubbedProduct("claude", probe: probe, settings: settings)
        let provider = providerProduct.defaultAccount
        let monitor = makeMonitor(providers: kept([providerProduct]))

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
    func `should show monitoring on while it runs and off once stopped, on the main actor (#182)`() async {
        // Reading and writing isMonitoring here compiles only because both this
        // suite and QuotaMonitor are @MainActor — the structural guard against
        // the #182 off-main mutation. The flow asserts the flag flips on, then off.
        let settings = makeSettingsRepository()
        let providerProduct = stubbedProduct("claude", probe: CountingUsageProbe(providerId: "claude"), settings: settings)
        let provider = providerProduct.defaultAccount
        let monitor = makeSuspendingMonitor(providers: kept([providerProduct]))

        let stream = monitor.startMonitoring(interval: .seconds(60))
        #expect(monitor.isMonitoring == true)

        for await _ in stream.prefix(1) {}
        monitor.stopMonitoring()

        #expect(monitor.isMonitoring == false)
    }

    /// Sub-minute and zero intervals clamp up to the 1-minute floor, while
    /// at- or above-floor intervals pass through unchanged (energy — #67).
    @Test
    func `should never refresh more often than once a minute (#67)`() {
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
    func `should slow the refresh to the slowest provider's minimum, like Claude API's 15 minutes (#204)`() {
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
    func `should not refresh while the display sleeps, and refresh once on wake (#204)`() async {
        let settings = makeSettingsRepository()
        let probe = CountingUsageProbe(providerId: "claude")
        let providerProduct = stubbedProduct("claude", probe: probe, settings: settings)
        let provider = providerProduct.defaultAccount
        let power = FakePowerStateProvider(asleep: true)
        let monitor = QuotaMonitor(
            providers: kept([providerProduct]),
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
    func `should refresh half as often on battery (#204)`() async {
        let settings = makeSettingsRepository()
        let providerProduct = stubbedProduct("claude", probe: CountingUsageProbe(providerId: "claude"), settings: settings)
        let provider = providerProduct.defaultAccount
        let power = FakePowerStateProvider(asleep: false, onBattery: true)
        let clock = RecordingClock()
        let monitor = QuotaMonitor(
            providers: kept([providerProduct]),
            clock: clock,
            powerStateProvider: power
        )

        let stream = monitor.startMonitoring(interval: .seconds(600))
        for await _ in stream {}

        // 600s → 1200s on battery (×2); CLI mode adds no provider floor.
        #expect(clock.durations == [.seconds(1200)])
    }

    @Test
    func `should refresh at the chosen cadence on AC power`() async {
        let settings = makeSettingsRepository()
        let providerProduct = stubbedProduct("claude", probe: CountingUsageProbe(providerId: "claude"), settings: settings)
        let provider = providerProduct.defaultAccount
        let power = FakePowerStateProvider(asleep: false, onBattery: false)
        let clock = RecordingClock()
        let monitor = QuotaMonitor(
            providers: kept([providerProduct]),
            clock: clock,
            powerStateProvider: power
        )

        let stream = monitor.startMonitoring(interval: .seconds(600))
        for await _ in stream {}

        #expect(clock.durations == [.seconds(600)])
    }

    // MARK: - Provider Collections

    @Test
    func `should list every registered login`() {
        // Given
        let settings = makeSettingsRepository()
        let claudeProduct = stubbedProduct("claude", probe: MockUsageProbe(), settings: settings)
        let claude = claudeProduct.defaultAccount
        let codexProduct = stubbedProduct("codex", probe: MockUsageProbe(), settings: settings)
        let codex = codexProduct.defaultAccount
        let monitor = makeMonitor(providers: kept([claudeProduct, codexProduct]))

        // Then
        #expect(monitor.logins.count == 2)
    }

    @Test
    func `should show only enabled logins in the lineup`() {
        // Given
        let settings = makeSettingsRepository()
        let claudeProduct = stubbedProduct("claude", probe: MockUsageProbe(), settings: settings)
        let claude = claudeProduct.defaultAccount
        let codexProduct = stubbedProduct("codex", probe: MockUsageProbe(), settings: settings)
        let codex = codexProduct.defaultAccount
        codex.isPaused = true
        let monitor = makeMonitor(providers: kept([claudeProduct, codexProduct]))

        // Then
        #expect(monitor.lineup.count == 1)
        #expect(monitor.lineup.first?.id == "claude")
    }

    // MARK: - Lowest Quota

    @Test
    func `should find the lowest quota across every provider`() async {
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
        let claudeProviderProduct = stubbedProduct("claude", probe: claudeProbe, settings: settings)
        let claudeProvider = claudeProviderProduct.defaultAccount
        let codexProviderProduct = stubbedProduct("codex", probe: codexProbe, settings: settings)
        let codexProvider = codexProviderProduct.defaultAccount
        let monitor = makeMonitor(providers: kept([claudeProviderProduct, codexProviderProduct]))

        await monitor.refreshAll()

        // When
        let lowest = monitor.lowestQuota()

        // Then
        #expect(lowest?.percentRemaining == 25)
    }

    @Test
    func `should find no lowest quota before any provider has quotas`() {
        // Given
        let settings = makeSettingsRepository()
        let monitor = makeMonitor(providers: kept([stubbedProduct("claude", probe: MockUsageProbe(), settings: settings)]))

        // Then
        #expect(monitor.lowestQuota() == nil)
    }

    // MARK: - Selection

    @Test
    func `should show the login of the selected provider`() {
        // Given
        let settings = makeSettingsRepository()
        let claudeProduct = stubbedProduct("claude", probe: MockUsageProbe(), settings: settings)
        let claude = claudeProduct.defaultAccount
        let codexProduct = stubbedProduct("codex", probe: MockUsageProbe(), settings: settings)
        let codex = codexProduct.defaultAccount
        let monitor = makeMonitor(providers: kept([claudeProduct, codexProduct]))

        // When
        monitor.selectedProviderId = "codex"

        // Then
        #expect(monitor.selectedLogin?.id == "codex")
    }

    @Test
    func `should show no selected login when the selected provider is disabled`() {
        // Given
        let settings = makeSettingsRepository()
        let claudeProduct = stubbedProduct("claude", probe: MockUsageProbe(), settings: settings)
        let claude = claudeProduct.defaultAccount
        claude.isPaused = true
        let monitor = makeMonitor(providers: kept([claudeProduct]))
        monitor.selectedProviderId = "claude"

        // Then
        #expect(monitor.selectedLogin == nil)
    }

    @Test
    func `should show the selected provider as healthy before its quotas arrive`() {
        // Given
        let settings = makeSettingsRepository()
        let claudeProduct = stubbedProduct("claude", probe: MockUsageProbe(), settings: settings)
        let claude = claudeProduct.defaultAccount
        let monitor = makeMonitor(providers: kept([claudeProduct]))

        // Then
        #expect(monitor.selectedProviderStatus == .healthy)
    }

    @Test
    func `should show the selected provider's status once its quotas arrive`() async {
        // Given
        let settings = makeSettingsRepository()
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(UsageSnapshot(
            providerId: "claude",
            quotas: [UsageQuota(percentRemaining: 15, quotaType: .session, providerId: "claude")],
            capturedAt: Date()
        ))
        let claudeProduct = stubbedProduct("claude", probe: probe, settings: settings)
        let claude = claudeProduct.defaultAccount
        let monitor = makeMonitor(providers: kept([claudeProduct]))

        await monitor.refresh(providerId: "claude")

        // Then
        #expect(monitor.selectedProviderStatus == .critical)
    }

    @Test
    func `should show the selected tab awaiting data, then critical once its login's usage arrives`() async {
        let settings = makeSettingsRepository()
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(UsageSnapshot(
            providerId: "claude",
            quotas: [UsageQuota(percentRemaining: 15, quotaType: .session, providerId: "claude")],
            capturedAt: Date()
        ))
        let claudeProduct = stubbedProduct("claude", probe: probe, settings: settings)
        let claude = claudeProduct.defaultAccount
        let monitor = makeMonitor(providers: kept([claudeProduct]))
        #expect(monitor.selectedLogins.map(\.id) == ["claude"])
        #expect(monitor.selectedTabStatus == nil)
        #expect(monitor.selectedBadge == .awaitingData)
        #expect(monitor.status(of: claude) == nil)

        await monitor.refresh(providerId: "claude")

        #expect(monitor.selectedTabStatus == .critical)
        #expect(monitor.selectedBadge == .quota(.critical))
        #expect(monitor.status(of: claude) == .critical)
    }

    @Test
    func `should select an enabled provider the person picks`() {
        // Given
        let settings = makeSettingsRepository()
        let claudeProduct = stubbedProduct("claude", probe: MockUsageProbe(), settings: settings)
        let claude = claudeProduct.defaultAccount
        let codexProduct = stubbedProduct("codex", probe: MockUsageProbe(), settings: settings)
        let codex = codexProduct.defaultAccount
        let monitor = makeMonitor(providers: kept([claudeProduct, codexProduct]))

        #expect(monitor.selectedProviderId == "claude")

        // When
        monitor.selectProvider(id: "codex")

        // Then
        #expect(monitor.selectedProviderId == "codex")
    }

    @Test
    func `should keep the current selection when the person picks a disabled provider`() {
        // Given
        let settings = makeSettingsRepository()
        let claudeProduct = stubbedProduct("claude", probe: MockUsageProbe(), settings: settings)
        let claude = claudeProduct.defaultAccount
        let codexProduct = stubbedProduct("codex", probe: MockUsageProbe(), settings: settings)
        let codex = codexProduct.defaultAccount
        codex.isPaused = true
        let monitor = makeMonitor(providers: kept([claudeProduct, codexProduct]))

        // When
        monitor.selectProvider(id: "codex")

        // Then - still claude because codex is disabled
        #expect(monitor.selectedProviderId == "claude")
    }

    @Test
    func `should open the pill in that slot even when every login of it is paused`() {
        // Given - gemini sits between two watched products with its login paused,
        // so the pills read: 1 Claude, 2 Gemini, 3 Codex
        let settings = makeSettingsRepository()
        let claudeProduct = stubbedProduct("claude", probe: MockUsageProbe(), settings: settings)
        let geminiProduct = stubbedProduct("gemini", probe: MockUsageProbe(), settings: settings)
        let gemini = geminiProduct.defaultAccount
        let codexProduct = stubbedProduct("codex", probe: MockUsageProbe(), settings: settings)
        gemini.isPaused = true
        let monitor = makeMonitor(providers: kept([claudeProduct, geminiProduct, codexProduct]))

        // When
        monitor.selectProvider(atPosition: 2)

        // Then - the second pill's page, paused, and no quota read from it
        #expect(monitor.selectedProviderId == "gemini")
        #expect(monitor.selectedTab?.id == "gemini")
        #expect(monitor.selectedBadge == .paused)
    }

    @Test
    func `should keep the current selection when the shortcut's slot has no provider`() {
        // Given
        let settings = makeSettingsRepository()
        let claudeProduct = stubbedProduct("claude", probe: MockUsageProbe(), settings: settings)
        let claude = claudeProduct.defaultAccount
        let codexProduct = stubbedProduct("codex", probe: MockUsageProbe(), settings: settings)
        let codex = codexProduct.defaultAccount
        let monitor = makeMonitor(providers: kept([claudeProduct, codexProduct]))

        // When
        monitor.selectProvider(atPosition: 3)
        monitor.selectProvider(atPosition: 0)

        // Then
        #expect(monitor.selectedProviderId == "claude")
    }

    @Test
    func `should select the first enabled provider at launch when the person turned Claude off`() {
        // Given - claude is off before init, so it has no page to open on
        let settings = makeSettingsRepository()
        let claudeProduct = stubbedProduct("claude", probe: MockUsageProbe(), settings: settings)
        let codexProduct = stubbedProduct("codex", probe: MockUsageProbe(), settings: settings)
        claudeProduct.isEnabled = false

        // When
        let monitor = makeMonitor(providers: kept([claudeProduct, codexProduct]))

        // Then - automatically selects codex (first enabled)
        #expect(monitor.selectedProviderId == "codex")
    }

    @Test
    func `should select Claude at launch when it is enabled`() {
        // Given
        let settings = makeSettingsRepository()
        let claudeProduct = stubbedProduct("claude", probe: MockUsageProbe(), settings: settings)
        let claude = claudeProduct.defaultAccount
        let codexProduct = stubbedProduct("codex", probe: MockUsageProbe(), settings: settings)
        let codex = codexProduct.defaultAccount

        // When
        let monitor = makeMonitor(providers: kept([claudeProduct, codexProduct]))

        // Then - keeps default claude
        #expect(monitor.selectedProviderId == "claude")
    }

    // MARK: - Refreshing State

    @Test
    func `should not show refreshing when no provider is syncing`() {
        // Given
        let settings = makeSettingsRepository()
        let claudeProduct = stubbedProduct("claude", probe: MockUsageProbe(), settings: settings)
        let claude = claudeProduct.defaultAccount
        let monitor = makeMonitor(providers: kept([claudeProduct]))

        // Then
        #expect(monitor.isRefreshing == false)
    }

    // MARK: - Providers Init

    @Test
    func `should list the logins of the providers the app keeps`() {
        // Given
        let settings = makeSettingsRepository()
        let repository = kept([
            stubbedProduct("claude", probe: MockUsageProbe(), settings: settings),
            stubbedProduct("codex", probe: MockUsageProbe(), settings: settings)
        ])

        // When
        let monitor = makeMonitor(providers: repository)

        // Then
        #expect(monitor.logins.count == 2)
    }

    // MARK: - Quota Alerter

    @Test
    func `should alert when a provider turns critical`() async {
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
        let claudeProduct = stubbedProduct("claude", probe: probe, settings: settings)
        let claude = claudeProduct.defaultAccount
        let monitor = makeMonitor(providers: kept([claudeProduct]), alerter: mockAlerter)

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
    func `should not alert when a provider's status stays healthy`() async {
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
        let claudeProduct = stubbedProduct("claude", probe: probe, settings: settings)
        let claude = claudeProduct.defaultAccount
        let monitor = makeMonitor(providers: kept([claudeProduct]), alerter: mockAlerter)

        // When - refresh twice with same status
        await monitor.refresh(providerId: "claude")
        await monitor.refresh(providerId: "claude")

        // Then - only notified once (first change from nil/healthy to healthy)
        // Actually, the first refresh won't trigger because healthy -> healthy
        verify(mockAlerter).alert(providerId: .any, previousStatus: .any, currentStatus: .any).called(0)
    }

    @Test
    func `should neither warn nor alert for an on-pace quota when status is pace-aware`() async {
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
        let claudeProduct = stubbedProduct("claude", probe: probe, settings: makeSettingsRepository())
        let claude = claudeProduct.defaultAccount
        let monitor = QuotaMonitor(
            providers: kept([claudeProduct]), alerter: mockAlerter, clock: TestClock(),
            statusPolicy: { .paceAware(burnRateThreshold: 1.5) }
        )

        // When
        await monitor.refresh(providerId: "claude")

        // Then — the notification agrees with the menu bar: no warning
        verify(mockAlerter).alert(providerId: .any, previousStatus: .any, currentStatus: .any).called(0)
        #expect(monitor.selectedProviderStatus == .healthy)
    }

    @Test
    func `should alert a warning for the same quota when status is absolute`() async {
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
        let claudeProduct = stubbedProduct("claude", probe: probe, settings: makeSettingsRepository())
        let claude = claudeProduct.defaultAccount
        let monitor = QuotaMonitor(
            providers: kept([claudeProduct]), alerter: mockAlerter, clock: TestClock(),
            statusPolicy: { .absolute }
        )

        await monitor.refresh(providerId: "claude")

        verify(mockAlerter).alert(
            providerId: .value("claude"), previousStatus: .value(.healthy), currentStatus: .value(.warning)
        ).called(1)
    }

    // MARK: - Disabled Provider Skipping

    @Test
    func `should not refresh a disabled provider`() async {
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
        let claudeProviderProduct = stubbedProduct("claude", probe: claudeProbe, settings: settings)
        let claudeProvider = claudeProviderProduct.defaultAccount
        let codexProviderProduct = stubbedProduct("codex", probe: codexProbe, settings: settings)
        let codexProvider = codexProviderProduct.defaultAccount
        codexProvider.isPaused = true

        let monitor = makeMonitor(providers: kept([claudeProviderProduct, codexProviderProduct]))

        // When
        await monitor.refreshAll()

        // Then - claude refreshed, codex skipped (no snapshot)
        #expect(claudeProvider.snapshot != nil)
        #expect(codexProvider.snapshot == nil)
    }

    @Test
    func `should leave a disabled provider out of the overall status`() async {
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
        let claudeProviderProduct = stubbedProduct("claude", probe: claudeProbe, settings: settings)
        let claudeProvider = claudeProviderProduct.defaultAccount
        let codexProviderProduct = stubbedProduct("codex", probe: codexProbe, settings: settings)
        let codexProvider = codexProviderProduct.defaultAccount

        let monitor = makeMonitor(providers: kept([claudeProviderProduct, codexProviderProduct]))

        // First refresh both
        await monitor.refreshAll()
        #expect(monitor.overallStatus == .critical)

        // Disable codex
        codexProvider.isPaused = true

        // Then - only claude's healthy status matters
        #expect(monitor.overallStatus == .healthy)
    }

    // MARK: - Pause and resume

    @Test
    func `should stay on a product whose only login the person paused`() {
        // Given
        let settings = makeSettingsRepository()
        let claudeProduct = stubbedProduct("claude", probe: MockUsageProbe(), settings: settings)
        let claude = claudeProduct.defaultAccount
        let codexProduct = stubbedProduct("codex", probe: MockUsageProbe(), settings: settings)
        let monitor = makeMonitor(providers: kept([claudeProduct, codexProduct]))
        monitor.selectedProviderId = "claude"

        // When - the person pauses the login the popover is showing
        monitor.pause(claude)

        // Then - the page is still there, paused, and the selection stays on it
        #expect(monitor.lineup.map(\.id) == ["codex"])
        #expect(monitor.selectedTab?.id == "claude")
        #expect(monitor.selectedTab?.paused.map(\.id) == ["claude"])
        #expect(monitor.selectedBadge == .paused)
    }

    @Test
    func `should keep the selection when the person resumes another login`() {
        // Given
        let settings = makeSettingsRepository()
        let claudeProduct = stubbedProduct("claude", probe: MockUsageProbe(), settings: settings)
        let codexProduct = stubbedProduct("codex", probe: MockUsageProbe(), settings: settings)
        let codex = codexProduct.defaultAccount
        codex.isPaused = true
        let monitor = makeMonitor(providers: kept([claudeProduct, codexProduct]))
        monitor.selectedProviderId = "claude"

        // When - the person resumes a login of another product
        monitor.resume(codex)

        // Then - the login is watched again, selection unchanged
        #expect(codex.isPaused == false)
        #expect(monitor.selectedProviderId == "claude")
    }
}
