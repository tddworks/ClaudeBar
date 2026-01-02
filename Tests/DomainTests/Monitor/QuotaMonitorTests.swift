import Testing
import Foundation
import Mockable
@testable import Domain

@Suite
struct QuotaMonitorTests {

    // MARK: - Single Provider Monitoring

    @Test
    func `monitor can refresh a provider by ID`() async throws {
        // Given
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
        let provider = ClaudeProvider(probe: probe)
        let monitor = QuotaMonitor(providers: AIProviders(providers: [provider]))

        // When
        await monitor.refresh(providerId: "claude")

        // Then
        #expect(provider.snapshot != nil)
        #expect(provider.snapshot?.quotas.count == 2)
        #expect(provider.snapshot?.quota(for: .session)?.percentRemaining == 65)
    }

    @Test
    func `monitor skips unavailable providers`() async {
        // Given
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(false)
        let provider = ClaudeProvider(probe: probe)
        let monitor = QuotaMonitor(providers: AIProviders(providers: [provider]))

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

        let claudeProvider = ClaudeProvider(probe: claudeProbe)
        let codexProvider = CodexProvider(probe: codexProbe)
        let monitor = QuotaMonitor(providers: AIProviders(providers: [claudeProvider, codexProvider]))

        // When
        await monitor.refreshAll()

        // Then
        #expect(claudeProvider.snapshot?.quota(for: .session)?.percentRemaining == 70)
        #expect(codexProvider.snapshot?.quota(for: .session)?.percentRemaining == 40)
    }

    @Test
    func `one provider failure does not affect others`() async {
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
        given(codexProbe).probe().willThrow(ProbeError.timeout)

        let claudeProvider = ClaudeProvider(probe: claudeProbe)
        let codexProvider = CodexProvider(probe: codexProbe)
        let monitor = QuotaMonitor(providers: AIProviders(providers: [claudeProvider, codexProvider]))

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

        let claudeProvider = ClaudeProvider(probe: claudeProbe)
        let codexProvider = CodexProvider(probe: codexProbe)
        let geminiProvider = GeminiProvider(probe: geminiProbe)
        let monitor = QuotaMonitor(providers: AIProviders(providers: [claudeProvider, codexProvider, geminiProvider]))

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
        let probe = MockUsageProbe()
        let provider = ClaudeProvider(probe: probe)
        let monitor = QuotaMonitor(providers: AIProviders(providers: [provider]))

        // When
        let found = monitor.provider(for: "claude")

        // Then
        #expect(found?.id == "claude")
    }

    @Test
    func `monitor returns nil for unknown provider ID`() async {
        // Given
        let monitor = QuotaMonitor(providers: AIProviders(providers: []))

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

        let claudeProvider = ClaudeProvider(probe: claudeProbe)
        let codexProvider = CodexProvider(probe: codexProbe)
        let monitor = QuotaMonitor(providers: AIProviders(providers: [claudeProvider, codexProvider]))

        await monitor.refreshAll()

        // When
        let overallStatus = monitor.overallStatus

        // Then - worst status (critical) wins
        #expect(overallStatus == .critical)
    }

    // MARK: - Continuous Monitoring

    @Test
    func `monitor can start continuous monitoring`() async throws {
        // Given
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(UsageSnapshot(
            providerId: "claude",
            quotas: [UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "claude")],
            capturedAt: Date()
        ))
        let provider = ClaudeProvider(probe: probe)
        let monitor = QuotaMonitor(providers: AIProviders(providers: [provider]))

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
    func `monitor stops when requested`() async throws {
        // Given
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(UsageSnapshot(
            providerId: "claude",
            quotas: [UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "claude")],
            capturedAt: Date()
        ))
        let provider = ClaudeProvider(probe: probe)
        let monitor = QuotaMonitor(providers: AIProviders(providers: [provider]))

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
        let claude = ClaudeProvider(probe: MockUsageProbe())
        let codex = CodexProvider(probe: MockUsageProbe())
        let monitor = QuotaMonitor(providers: AIProviders(providers: [claude, codex]))

        // Then
        #expect(monitor.allProviders.count == 2)
    }

    @Test
    func `enabledProviders returns only enabled providers`() {
        // Given
        let claude = ClaudeProvider(probe: MockUsageProbe())
        let codex = CodexProvider(probe: MockUsageProbe())
        codex.isEnabled = false
        let monitor = QuotaMonitor(providers: AIProviders(providers: [claude, codex]))

        // Then
        #expect(monitor.enabledProviders.count == 1)
        #expect(monitor.enabledProviders.first?.id == "claude")
    }

    // MARK: - Dynamic Provider Management

    @Test
    func `addProvider adds new provider`() {
        // Given
        let claude = ClaudeProvider(probe: MockUsageProbe())
        let monitor = QuotaMonitor(providers: [claude])

        #expect(monitor.allProviders.count == 1)

        // When
        let codex = CodexProvider(probe: MockUsageProbe())
        monitor.addProvider(codex)

        // Then
        #expect(monitor.allProviders.count == 2)
        #expect(monitor.provider(for: "codex") != nil)
    }

    @Test
    func `removeProvider removes provider by id`() {
        // Given
        let claude = ClaudeProvider(probe: MockUsageProbe())
        let codex = CodexProvider(probe: MockUsageProbe())
        let monitor = QuotaMonitor(providers: AIProviders(providers: [claude, codex]))

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

        let claudeProvider = ClaudeProvider(probe: claudeProbe)
        let codexProvider = CodexProvider(probe: codexProbe)
        let monitor = QuotaMonitor(providers: AIProviders(providers: [claudeProvider, codexProvider]))

        await monitor.refreshAll()

        // When
        let lowest = monitor.lowestQuota()

        // Then
        #expect(lowest?.percentRemaining == 25)
    }

    @Test
    func `lowestQuota returns nil when no snapshots`() {
        // Given
        let monitor = QuotaMonitor(providers: [ClaudeProvider(probe: MockUsageProbe())])

        // Then
        #expect(monitor.lowestQuota() == nil)
    }

    // MARK: - Selection

    @Test
    func `selectedProvider returns provider matching selectedProviderId`() {
        // Given
        let claude = ClaudeProvider(probe: MockUsageProbe())
        let codex = CodexProvider(probe: MockUsageProbe())
        let monitor = QuotaMonitor(providers: AIProviders(providers: [claude, codex]))

        // When
        monitor.selectedProviderId = "codex"

        // Then
        #expect(monitor.selectedProvider?.id == "codex")
    }

    @Test
    func `selectedProvider returns nil when selected provider is disabled`() {
        // Given
        let claude = ClaudeProvider(probe: MockUsageProbe())
        claude.isEnabled = false
        let monitor = QuotaMonitor(providers: [claude])
        monitor.selectedProviderId = "claude"

        // Then
        #expect(monitor.selectedProvider == nil)
    }

    @Test
    func `selectedProviderStatus returns healthy when no snapshot`() {
        // Given
        let claude = ClaudeProvider(probe: MockUsageProbe())
        let monitor = QuotaMonitor(providers: [claude])

        // Then
        #expect(monitor.selectedProviderStatus == .healthy)
    }

    @Test
    func `selectedProviderStatus returns provider status when snapshot exists`() async {
        // Given
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(UsageSnapshot(
            providerId: "claude",
            quotas: [UsageQuota(percentRemaining: 15, quotaType: .session, providerId: "claude")],
            capturedAt: Date()
        ))
        let claude = ClaudeProvider(probe: probe)
        let monitor = QuotaMonitor(providers: [claude])

        await monitor.refresh(providerId: "claude")

        // Then
        #expect(monitor.selectedProviderStatus == .critical)
    }

    @Test
    func `selectProvider updates selectedProviderId for enabled provider`() {
        // Given
        let claude = ClaudeProvider(probe: MockUsageProbe())
        let codex = CodexProvider(probe: MockUsageProbe())
        let monitor = QuotaMonitor(providers: AIProviders(providers: [claude, codex]))

        #expect(monitor.selectedProviderId == "claude")

        // When
        monitor.selectProvider(id: "codex")

        // Then
        #expect(monitor.selectedProviderId == "codex")
    }

    @Test
    func `selectProvider ignores disabled provider`() {
        // Given
        let claude = ClaudeProvider(probe: MockUsageProbe())
        let codex = CodexProvider(probe: MockUsageProbe())
        codex.isEnabled = false
        let monitor = QuotaMonitor(providers: AIProviders(providers: [claude, codex]))

        // When
        monitor.selectProvider(id: "codex")

        // Then - still claude because codex is disabled
        #expect(monitor.selectedProviderId == "claude")
    }

    @Test
    func `ensureValidSelection picks first enabled when current is invalid`() {
        // Given
        let claude = ClaudeProvider(probe: MockUsageProbe())
        let codex = CodexProvider(probe: MockUsageProbe())
        let monitor = QuotaMonitor(providers: AIProviders(providers: [claude, codex]))
        monitor.selectedProviderId = "unknown"

        // When
        monitor.ensureValidSelection()

        // Then
        #expect(monitor.selectedProviderId == "claude")
    }

    @Test
    func `ensureValidSelection keeps valid selection`() {
        // Given
        let claude = ClaudeProvider(probe: MockUsageProbe())
        let codex = CodexProvider(probe: MockUsageProbe())
        let monitor = QuotaMonitor(providers: AIProviders(providers: [claude, codex]))
        monitor.selectedProviderId = "codex"

        // When
        monitor.ensureValidSelection()

        // Then - keeps codex
        #expect(monitor.selectedProviderId == "codex")
    }

    @Test
    func `ensureValidSelection updates when selected provider becomes disabled`() {
        // Given
        let claude = ClaudeProvider(probe: MockUsageProbe())
        let codex = CodexProvider(probe: MockUsageProbe())
        let monitor = QuotaMonitor(providers: AIProviders(providers: [claude, codex]))
        monitor.selectedProviderId = "codex"
        codex.isEnabled = false

        // When
        monitor.ensureValidSelection()

        // Then - switches to claude
        #expect(monitor.selectedProviderId == "claude")
    }

    // MARK: - Refreshing State

    @Test
    func `isRefreshing returns false when no providers syncing`() {
        // Given
        let claude = ClaudeProvider(probe: MockUsageProbe())
        let monitor = QuotaMonitor(providers: [claude])

        // Then
        #expect(monitor.isRefreshing == false)
    }

    // MARK: - AIProviders Repository Init

    @Test
    func `init with AIProviders repository works`() {
        // Given
        let repository = AIProviders(providers: [
            ClaudeProvider(probe: MockUsageProbe()),
            CodexProvider(probe: MockUsageProbe())
        ])

        // When
        let monitor = QuotaMonitor(providers: repository)

        // Then
        #expect(monitor.allProviders.count == 2)
    }

    // MARK: - Status Listener

    @Test
    func `status listener is notified on status change`() async {
        // Given
        let mockListener = MockQuotaStatusListener()
        given(mockListener).onStatusChanged(providerId: .any, oldStatus: .any, newStatus: .any).willReturn(())

        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(UsageSnapshot(
            providerId: "claude",
            quotas: [UsageQuota(percentRemaining: 15, quotaType: .session, providerId: "claude")],
            capturedAt: Date()
        ))
        let claude = ClaudeProvider(probe: probe)
        let monitor = QuotaMonitor(providers: [claude], statusListener: mockListener)

        // When
        await monitor.refresh(providerId: "claude")

        // Then
        verify(mockListener).onStatusChanged(
            providerId: .value("claude"),
            oldStatus: .value(.healthy),
            newStatus: .value(.critical)
        ).called(1)
    }

    @Test
    func `status listener not notified when status unchanged`() async {
        // Given
        let mockListener = MockQuotaStatusListener()
        given(mockListener).onStatusChanged(providerId: .any, oldStatus: .any, newStatus: .any).willReturn(())

        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(UsageSnapshot(
            providerId: "claude",
            quotas: [UsageQuota(percentRemaining: 70, quotaType: .session, providerId: "claude")],
            capturedAt: Date()
        ))
        let claude = ClaudeProvider(probe: probe)
        let monitor = QuotaMonitor(providers: [claude], statusListener: mockListener)

        // When - refresh twice with same status
        await monitor.refresh(providerId: "claude")
        await monitor.refresh(providerId: "claude")

        // Then - only notified once (first change from nil/healthy to healthy)
        // Actually, the first refresh won't trigger because healthy -> healthy
        verify(mockListener).onStatusChanged(providerId: .any, oldStatus: .any, newStatus: .any).called(0)
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

        let claudeProvider = ClaudeProvider(probe: claudeProbe)
        let codexProvider = CodexProvider(probe: codexProbe)
        codexProvider.isEnabled = false

        let monitor = QuotaMonitor(providers: AIProviders(providers: [claudeProvider, codexProvider]))

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

        let claudeProvider = ClaudeProvider(probe: claudeProbe)
        let codexProvider = CodexProvider(probe: codexProbe)

        let monitor = QuotaMonitor(providers: AIProviders(providers: [claudeProvider, codexProvider]))

        // First refresh both
        await monitor.refreshAll()
        #expect(monitor.overallStatus == .critical)

        // Disable codex
        codexProvider.isEnabled = false

        // Then - only claude's healthy status matters
        #expect(monitor.overallStatus == .healthy)
    }
}
