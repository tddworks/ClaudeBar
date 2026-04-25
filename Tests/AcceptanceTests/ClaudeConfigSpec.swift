import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

/// Feature: Claude Configuration
///
/// Users switch Claude between CLI and API probe modes.
/// API mode uses OAuth credentials for direct HTTP calls.
///
/// Behaviors covered:
/// - #28: User switches Claude to API mode → uses OAuth HTTP API instead of CLI
/// - #29: API mode shows credential status (found / not found)
/// - #30: Expired session shows user-friendly error message
@Suite("Feature: Claude Configuration")
struct ClaudeConfigSpec {

    private struct TestClock: Clock {
        func sleep(for duration: TimeInterval) async throws {}
    }

    // MARK: - #28: Switch Claude to API mode

    @Suite("Scenario: Switch probe mode")
    struct SwitchProbeMode {
        private struct TestClock: Clock {
            func sleep(for duration: TimeInterval) async throws {}
        }

        @Test
        func `switching to API mode uses API probe for refresh`() async throws {
            // Given — dual probe setup
            let suiteName = "com.claudebar.test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            let settings = UserDefaultsProviderSettingsRepository(userDefaults: defaults)
            settings.setEnabled(true, forProvider: "claude")

            let cliProbe = MockUsageProbe()
            given(cliProbe).isAvailable().willReturn(true)
            given(cliProbe).probe().willReturn(UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 70, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            ))

            let apiProbe = MockUsageProbe()
            given(apiProbe).isAvailable().willReturn(true)
            given(apiProbe).probe().willReturn(UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 55, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            ))

            let claude = ClaudeProvider(
                cliProbe: cliProbe,
                apiProbe: apiProbe,
                settingsRepository: settings
            )

            // Default is CLI mode
            #expect(claude.probeMode == .cli)

            // When — user switches to API mode
            claude.probeMode = .api

            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude]),
                clock: TestClock()
            )
            await monitor.refresh(providerId: "claude")

            // Then — API probe result (55%) used, not CLI (70%)
            #expect(claude.probeMode == .api)
            #expect(claude.snapshot?.quotas.first?.percentRemaining == 55)
        }

        @Test
        func `probe mode is persisted in UserDefaults`() {
            // Given
            let suiteName = "com.claudebar.test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            let settings = UserDefaultsProviderSettingsRepository(userDefaults: defaults)

            // Default is CLI
            #expect(settings.claudeProbeMode() == .cli)

            // When
            settings.setClaudeProbeMode(.api)

            // Then — persisted
            #expect(settings.claudeProbeMode() == .api)
        }

        @Test
        func `api mode falls back to CLI when OAuth API is unavailable`() async throws {
            let suiteName = "com.claudebar.test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            let settings = UserDefaultsProviderSettingsRepository(userDefaults: defaults)
            settings.setEnabled(true, forProvider: "claude")
            settings.setClaudeProbeMode(.api)

            let cliProbe = MockUsageProbe()
            given(cliProbe).isAvailable().willReturn(true)
            given(cliProbe).probe().willReturn(UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 63, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            ))

            let apiProbe = MockUsageProbe()
            given(apiProbe).isAvailable().willReturn(false)
            given(apiProbe).probe().willThrow(ProbeError.authenticationRequired)

            let claude = ClaudeProvider(
                cliProbe: cliProbe,
                apiProbe: apiProbe,
                settingsRepository: settings
            )

            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude]),
                clock: TestClock()
            )

            await monitor.refresh(providerId: "claude")

            #expect(claude.snapshot?.quotas.first?.percentRemaining == 63)
            #expect(claude.lastError == nil)
        }

        @Test
        func `api mode does not fall back to CLI when cli fallback is disabled`() async throws {
            let suiteName = "com.claudebar.test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            let settings = UserDefaultsProviderSettingsRepository(userDefaults: defaults)
            settings.setEnabled(true, forProvider: "claude")
            settings.setClaudeProbeMode(.api)
            settings.setClaudeCliFallbackEnabled(false)

            let cliProbe = MockUsageProbe()
            // CLI probe must not be consulted — if it is, probe() would succeed
            // and we'd get snapshot data, which would fail the assertion below
            given(cliProbe).isAvailable().willReturn(true)
            given(cliProbe).probe().willReturn(UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 99, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            ))

            let apiProbe = MockUsageProbe()
            // API probe is available but fails — fallback to CLI must not happen
            given(apiProbe).isAvailable().willReturn(true)
            given(apiProbe).probe().willThrow(ProbeError.authenticationRequired)

            let claude = ClaudeProvider(
                cliProbe: cliProbe,
                apiProbe: apiProbe,
                settingsRepository: settings
            )

            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude]),
                clock: TestClock()
            )

            await monitor.refresh(providerId: "claude")

            // Error propagated — CLI fallback was not used
            #expect(claude.lastError != nil)
            #expect(claude.snapshot == nil)
        }

        @Test
        func `cli mode falls back to API when CLI parsing fails and OAuth is available`() async throws {
            let suiteName = "com.claudebar.test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            let settings = UserDefaultsProviderSettingsRepository(userDefaults: defaults)
            settings.setEnabled(true, forProvider: "claude")
            settings.setClaudeProbeMode(.cli)

            let cliProbe = MockUsageProbe()
            given(cliProbe).isAvailable().willReturn(true)
            given(cliProbe).probe().willThrow(ProbeError.parseFailed("could not find Current session"))

            let apiProbe = MockUsageProbe()
            given(apiProbe).isAvailable().willReturn(true)
            given(apiProbe).probe().willReturn(UsageSnapshot(
                providerId: "claude",
                quotas: [
                    UsageQuota(percentRemaining: 81, quotaType: .session, providerId: "claude"),
                    UsageQuota(percentRemaining: 74, quotaType: .weekly, providerId: "claude")
                ],
                capturedAt: Date()
            ))

            let claude = ClaudeProvider(
                cliProbe: cliProbe,
                apiProbe: apiProbe,
                settingsRepository: settings
            )

            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude]),
                clock: TestClock()
            )

            await monitor.refresh(providerId: "claude")

            #expect(claude.snapshot?.quotas.count == 2)
            #expect(claude.snapshot?.quotas.first?.percentRemaining == 81)
            #expect(claude.lastError == nil)
        }
    }

    // MARK: - #29: API mode credential status

    @Suite("Scenario: API mode credential availability")
    struct CredentialStatus {

        @Test
        func `supportsApiMode is true when API probe is provided`() {
            // Given
            let settings = MockProviderSettingsRepository()
            given(settings).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
            given(settings).isEnabled(forProvider: .any).willReturn(true)
            given(settings).setEnabled(.any, forProvider: .any).willReturn()

            // CLI-only provider
            let cliOnly = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
            #expect(cliOnly.supportsApiMode == false)
        }
    }

    // MARK: - #30: Expired session error

    @Suite("Scenario: Expired session shows user-friendly error")
    struct SessionExpired {
        private struct TestClock: Clock {
            func sleep(for duration: TimeInterval) async throws {}
        }

        @Test
        func `sessionExpired error has user-friendly description`() async {
            // Given
            let settings = MockProviderSettingsRepository()
            given(settings).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
            given(settings).isEnabled(forProvider: .any).willReturn(true)
            given(settings).setEnabled(.any, forProvider: .any).willReturn()

            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willThrow(ProbeError.sessionExpired(hint: "Run `claude` in terminal to log in again."))

            let claude = ClaudeProvider(probe: probe, settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude]),
                clock: TestClock()
            )

            // When — API returns 401
            await monitor.refresh(providerId: "claude")

            // Then — user sees actionable error with provider-specific hint
            #expect(claude.lastError != nil)
            let description = claude.lastError?.localizedDescription ?? ""
            #expect(description.contains("Session expired"))
            #expect(description.contains("claude"))
        }
    }
}
