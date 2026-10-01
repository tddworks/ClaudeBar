import Testing
import Foundation
import Mockable
@testable import Domain

@Suite("ClaudeProvider Tests")
@MainActor
struct ClaudeProviderTests {

    private func makeSettingsRepository() -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(mock).isEnabled(forProvider: .any).willReturn(true)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        return mock
    }

    // MARK: - Identity

    @Test
    func `claude provider has correct id`() {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(claude.id == "claude")
    }

    @Test
    func `claude provider has correct name`() {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(claude.name == "Claude")
    }

    @Test
    func `claude provider has correct cliCommand`() {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(claude.cliCommand == "claude")
    }

    @Test
    func `claude provider has dashboard URL pointing to anthropic`() {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(claude.dashboardURL != nil)
        #expect(claude.dashboardURL?.host?.contains("anthropic") == true)
    }

    @Test
    func `claude provider is enabled by default`() {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(claude.isEnabled == true)
    }

    // MARK: - State

    @Test
    func `claude provider starts with no snapshot`() {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(claude.snapshot == nil)
    }

    @Test
    func `claude provider starts not syncing`() {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(claude.isSyncing == false)
    }

    @Test
    func `claude provider starts with no error`() {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(claude.lastError == nil)
    }

    // MARK: - Delegation

    @Test
    func `claude provider delegates isAvailable to probe`() async {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).isAvailable().willReturn(true)
        let claude = ClaudeProvider(probe: mockProbe, settingsRepository: settings)

        let isAvailable = await claude.isAvailable()
        #expect(isAvailable == true)
    }

    @Test
    func `isAvailable returns false in API mode when API unavailable and CLI fallback disabled`() async {
        let settings = FakeClaudeSettings(probeMode: .api, cliFallbackEnabled: false)
        let cliProbe = MockUsageProbe()
        given(cliProbe).isAvailable().willReturn(true)
        let apiProbe = MockUsageProbe()
        given(apiProbe).isAvailable().willReturn(false)
        let claude = ClaudeProvider(cliProbe: cliProbe, apiProbe: apiProbe, settingsRepository: settings)

        #expect(await claude.isAvailable() == false)
    }

    @Test
    func `isAvailable returns true in API mode when API unavailable but CLI fallback enabled`() async {
        let settings = FakeClaudeSettings(probeMode: .api, cliFallbackEnabled: true)
        let cliProbe = MockUsageProbe()
        given(cliProbe).isAvailable().willReturn(true)
        let apiProbe = MockUsageProbe()
        given(apiProbe).isAvailable().willReturn(false)
        let claude = ClaudeProvider(cliProbe: cliProbe, apiProbe: apiProbe, settingsRepository: settings)

        #expect(await claude.isAvailable() == true)
    }

    @Test
    func `claude provider delegates refresh to probe`() async throws {
        let settings = makeSettingsRepository()
        let expectedSnapshot = UsageSnapshot(providerId: "claude", quotas: [], capturedAt: Date())
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(expectedSnapshot)
        let claude = ClaudeProvider(probe: mockProbe, settingsRepository: settings)

        let snapshot = try await claude.refresh()
        #expect(snapshot.quotas.isEmpty)
    }

    // MARK: - Snapshot Storage

    @Test
    func `claude provider stores snapshot after refresh`() async throws {
        let settings = makeSettingsRepository()
        let expectedSnapshot = UsageSnapshot(
            providerId: "claude",
            quotas: [UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "claude")],
            capturedAt: Date()
        )
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(expectedSnapshot)
        let claude = ClaudeProvider(probe: mockProbe, settingsRepository: settings)

        #expect(claude.snapshot == nil)
        _ = try await claude.refresh()
        #expect(claude.snapshot != nil)
        #expect(claude.snapshot?.quotas.first?.percentRemaining == 50)
    }

    // MARK: - Error Handling

    @Test
    func `claude provider stores error on refresh failure`() async {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willThrow(ProbeError.timeout)
        let claude = ClaudeProvider(probe: mockProbe, settingsRepository: settings)

        #expect(claude.lastError == nil)
        do {
            _ = try await claude.refresh()
        } catch {
            // Expected
        }
        #expect(claude.lastError != nil)
    }

    // MARK: - Syncing State

    @Test
    func `claude provider resets isSyncing after refresh completes`() async throws {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(UsageSnapshot(providerId: "claude", quotas: [], capturedAt: Date()))
        let claude = ClaudeProvider(probe: mockProbe, settingsRepository: settings)

        #expect(claude.isSyncing == false)
        _ = try await claude.refresh()
        #expect(claude.isSyncing == false)
    }

    // MARK: - Equality via ID

    @Test
    func `two claude providers have same id`() {
        let settings = makeSettingsRepository()
        let provider1 = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let provider2 = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(provider1.id == provider2.id)
    }

    // MARK: - Error Propagation When Both Probes Fail

    @Test
    func `refresh does not invoke CLI fallback when API returns rateLimited`() async {
        // When the API probe is rate-limited, the CLI probe talks to the
        // same Anthropic backend (subject to the same per-token throttle)
        // AND it's currently broken in the field. The rate-limit error
        // should surface immediately without the CLI probe being touched.
        let settings = FakeClaudeSettings(probeMode: .api, cliFallbackEnabled: true)

        let retryAt = Date().addingTimeInterval(300)
        let apiProbe = MockUsageProbe()
        given(apiProbe).isAvailable().willReturn(true)
        given(apiProbe).probe().willThrow(ProbeError.rateLimited(retryAt: retryAt))

        let cliProbe = MockUsageProbe()
        given(cliProbe).isAvailable().willReturn(true)

        let claude = ClaudeProvider(cliProbe: cliProbe, apiProbe: apiProbe, settingsRepository: settings)

        do {
            _ = try await claude.refresh()
            Issue.record("Expected refresh to throw")
        } catch let error as ProbeError {
            #expect(error == .rateLimited(retryAt: retryAt))
        } catch {
            Issue.record("Expected ProbeError, got \(error)")
        }

        // The CLI probe must never be invoked when the primary error is
        // an upstream rate-limit; fallback would amplify the throttle.
        verify(cliProbe).probe().called(0)
    }

    @Test
    func `refresh surfaces primary API error when CLI fallback also fails`() async {
        // API mode with CLI fallback enabled: API probe throws .rateLimited
        // (the real root cause), CLI fallback throws .parseFailed (a red
        // herring caused by the broken /usage stdout capture). The user
        // should see the rate-limit error, not the parse failure.
        let settings = FakeClaudeSettings(probeMode: .api, cliFallbackEnabled: true)

        let retryAt = Date().addingTimeInterval(300)
        let apiProbe = MockUsageProbe()
        given(apiProbe).isAvailable().willReturn(true)
        given(apiProbe).probe().willThrow(ProbeError.rateLimited(retryAt: retryAt))

        let cliProbe = MockUsageProbe()
        given(cliProbe).isAvailable().willReturn(true)
        given(cliProbe).probe().willThrow(ProbeError.parseFailed("Could not find session usage"))

        let claude = ClaudeProvider(cliProbe: cliProbe, apiProbe: apiProbe, settingsRepository: settings)

        do {
            _ = try await claude.refresh()
            Issue.record("Expected refresh to throw")
        } catch let error as ProbeError {
            #expect(error == .rateLimited(retryAt: retryAt))
            #expect(claude.lastError as? ProbeError == .rateLimited(retryAt: retryAt))
        } catch {
            Issue.record("Expected ProbeError, got \(error)")
        }
    }

    // MARK: - Fallback Gate (issue #317)

    @Test
    func `refresh falls back to the API probe even when its isAvailable says no`() async throws {
        // `isAvailable()` is a second, independently implemented answer to "can
        // this probe work?", asked before every fallback. When it said no the
        // rescue was skipped and nothing said so — 115 refreshes in the log
        // attached to #317 where only the broken CLI probe ever ran, and the user
        // saw "Claude Unavailable" throughout. The API probe decides for itself
        // inside `probe()`, and its error is discarded in favour of the primary
        // one, so the pre-check bought nothing but silent skips.
        let settings = FakeClaudeSettings(probeMode: .cli)

        let cliProbe = MockUsageProbe()
        given(cliProbe).isAvailable().willReturn(true)
        given(cliProbe).probe().willThrow(ProbeError.parseFailed("Could not find session usage"))

        let apiSnapshot = UsageSnapshot(
            providerId: "claude",
            quotas: [],
            capturedAt: Date(),
            accountTier: .claudeMax
        )
        let apiProbe = MockUsageProbe()
        given(apiProbe).isAvailable().willReturn(false)
        given(apiProbe).probe().willReturn(apiSnapshot)

        let claude = ClaudeProvider(cliProbe: cliProbe, apiProbe: apiProbe, settingsRepository: settings)

        let snapshot = try await claude.refresh()
        #expect(snapshot.accountTier == .claudeMax)
    }

    @Test
    func `refresh surfaces the CLI error when the API fallback also fails`() async throws {
        // Dropping the availability pre-check must not change which error wins:
        // the primary failure is still the one the user is shown.
        let settings = FakeClaudeSettings(probeMode: .cli)

        let cliProbe = MockUsageProbe()
        given(cliProbe).isAvailable().willReturn(true)
        given(cliProbe).probe().willThrow(ProbeError.parseFailed("Could not find session usage"))

        let apiProbe = MockUsageProbe()
        given(apiProbe).isAvailable().willReturn(false)
        given(apiProbe).probe().willThrow(ProbeError.authenticationRequired)

        let claude = ClaudeProvider(cliProbe: cliProbe, apiProbe: apiProbe, settingsRepository: settings)

        await #expect(throws: ProbeError.parseFailed("Could not find session usage")) {
            try await claude.refresh()
        }
    }

    @Test
    func `refresh does not fall back to the CLI when cliFallbackEnabled is false`() async throws {
        // #317 removed the `isAvailable()` pre-check from *both* directions, so
        // the one gate left has to carry its own weight: `claude.cliFallbackEnabled`
        // is the user's switch for running the CLI in the background, and with it
        // off the API probe's failure must stand alone — no CLI subprocess, and the
        // API's own error is what the user sees.
        let settings = FakeClaudeSettings(probeMode: .api, cliFallbackEnabled: false)

        let apiProbe = MockUsageProbe()
        given(apiProbe).isAvailable().willReturn(true)
        given(apiProbe).probe().willThrow(ProbeError.parseFailed("Could not read usage"))

        let cliProbe = MockUsageProbe()
        given(cliProbe).isAvailable().willReturn(true)

        let claude = ClaudeProvider(cliProbe: cliProbe, apiProbe: apiProbe, settingsRepository: settings)

        await #expect(throws: ProbeError.parseFailed("Could not read usage")) {
            try await claude.refresh()
        }
        // The API probe is primary here, so its error is the one the user is
        // shown and the one `lastError` holds — the CLI's error never happens,
        // because the CLI is never launched.
        #expect(claude.lastError as? ProbeError == .parseFailed("Could not read usage"))
        // The switch is the whole point: the CLI must never be launched.
        verify(cliProbe).probe().called(0)
    }

    @Test
    func `a failed fallback probe is reported so the rescue is not invisible`() async {
        // #317 made this path run on every failed probe, and the fallback's
        // error used to be swallowed by a bare `catch { }`. The user still sees
        // the primary error, but "the rescue ran and failed" and "the rescue
        // never ran" then looked identical in the log — which is the same
        // complaint the removed isAvailable() gate drew.
        let settings = FakeClaudeSettings(probeMode: .cli)

        let cliProbe = MockUsageProbe()
        given(cliProbe).isAvailable().willReturn(true)
        given(cliProbe).probe().willThrow(ProbeError.parseFailed("Could not find session usage"))

        let apiProbe = MockUsageProbe()
        given(apiProbe).isAvailable().willReturn(false)
        given(apiProbe).probe().willThrow(ProbeError.authenticationRequired)

        let recorder = DiagnosticRecorder()
        let claude = ClaudeProvider(
            cliProbe: cliProbe,
            apiProbe: apiProbe,
            settingsRepository: settings,
            diagnose: { recorder.record($0) }
        )

        _ = try? await claude.refresh()

        // One line, naming the fallback probe and its error, and never any
        // credential value. `ProbeError`'s own wording is capitalised
        // ("Authentication required…"), so the kind is matched case-insensitively.
        #expect(recorder.messages.count == 1)
        let message = recorder.messages.first ?? ""
        #expect(message.contains("API"))
        #expect(message.lowercased().contains("authentication"))
    }

    // MARK: - Background Refresh Floor (issue #204)

    @Test
    func `background refresh floor is 15 minutes in API mode`() {
        let settings = FakeClaudeSettings(probeMode: .api)
        let claude = ClaudeProvider(
            cliProbe: MockUsageProbe(),
            apiProbe: MockUsageProbe(),
            settingsRepository: settings
        )

        // API mode floors the background cadence to the API snapshot-cache TTL.
        #expect(claude.backgroundRefreshFloor == .seconds(900))
    }

    @Test
    func `background refresh floor is nil in CLI mode`() {
        let settings = FakeClaudeSettings(probeMode: .cli)
        let claude = ClaudeProvider(
            cliProbe: MockUsageProbe(),
            apiProbe: MockUsageProbe(),
            settingsRepository: settings
        )

        // CLI mode imposes no floor — it keeps the user's chosen interval.
        #expect(claude.backgroundRefreshFloor == nil)
    }
}

// MARK: - Test Helpers

/// Collects what the provider reports through its `diagnose` sink.
@MainActor
private final class DiagnosticRecorder {
    private(set) var messages: [String] = []
    func record(_ message: String) { messages.append(message) }
}

private final class FakeClaudeSettings: ClaudeSettingsRepository, @unchecked Sendable {
    var probeMode: ClaudeProbeMode
    var cliFallbackEnabled: Bool

    init(probeMode: ClaudeProbeMode = .cli, cliFallbackEnabled: Bool = true) {
        self.probeMode = probeMode
        self.cliFallbackEnabled = cliFallbackEnabled
    }

    func isEnabled(forProvider id: String) -> Bool { true }
    func isEnabled(forProvider id: String, defaultValue: Bool) -> Bool { true }
    func setEnabled(_ enabled: Bool, forProvider id: String) {}
    func customCardURL(forProvider id: String) -> String? { nil }
    func setCustomCardURL(_ url: String?, forProvider id: String) {}
    func claudeProbeMode() -> ClaudeProbeMode { probeMode }
    func setClaudeProbeMode(_ mode: ClaudeProbeMode) { probeMode = mode }
    func claudeCliFallbackEnabled() -> Bool { cliFallbackEnabled }
    func setClaudeCliFallbackEnabled(_ enabled: Bool) { cliFallbackEnabled = enabled }
}
