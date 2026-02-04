import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

/// Feature: Codex Configuration
///
/// Users switch Codex between RPC and API probe modes.
/// API mode uses OAuth credentials from ~/.codex/auth.json.
///
/// Behaviors covered:
/// - #33: User switches Codex to API mode → uses ChatGPT backend API instead of RPC
/// - #34: API mode shows credential status (found / not found)
@Suite("Feature: Codex Configuration")
struct CodexConfigSpec {

    private struct TestClock: Clock {
        func sleep(for duration: Duration) async throws {}
        func sleep(nanoseconds: UInt64) async throws {}
    }

    // MARK: - #33: Switch Codex to API mode

    @Suite("Scenario: Switch probe mode")
    struct SwitchProbeMode {
        private struct TestClock: Clock {
            func sleep(for duration: Duration) async throws {}
            func sleep(nanoseconds: UInt64) async throws {}
        }

        @Test
        func `switching to API mode uses API probe for refresh`() async throws {
            // Given — dual probe setup with isolated UserDefaults
            let suiteName = "com.claudebar.test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            let settings = UserDefaultsProviderSettingsRepository(userDefaults: defaults)
            settings.setEnabled(true, forProvider: "codex")

            let rpcProbe = MockUsageProbe()
            given(rpcProbe).isAvailable().willReturn(true)
            given(rpcProbe).probe().willReturn(UsageSnapshot(
                providerId: "codex",
                quotas: [UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "codex")],
                capturedAt: Date()
            ))

            let apiProbe = MockUsageProbe()
            given(apiProbe).isAvailable().willReturn(true)
            given(apiProbe).probe().willReturn(UsageSnapshot(
                providerId: "codex",
                quotas: [UsageQuota(percentRemaining: 45, quotaType: .session, providerId: "codex")],
                capturedAt: Date()
            ))

            let codex = CodexProvider(
                rpcProbe: rpcProbe,
                apiProbe: apiProbe,
                settingsRepository: settings
            )

            // Default is RPC mode
            #expect(codex.probeMode == .rpc)

            // When — user switches to API mode
            codex.probeMode = .api

            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [codex]),
                clock: TestClock()
            )
            await monitor.refresh(providerId: "codex")

            // Then — API probe result (45%) used, not RPC (80%)
            #expect(codex.probeMode == .api)
            #expect(codex.snapshot?.quotas.first?.percentRemaining == 45)
        }

        @Test
        func `probe mode is persisted in UserDefaults`() {
            // Given
            let suiteName = "com.claudebar.test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            let settings = UserDefaultsProviderSettingsRepository(userDefaults: defaults)

            // Default is RPC
            #expect(settings.codexProbeMode() == .rpc)

            // When
            settings.setCodexProbeMode(.api)

            // Then — persisted
            #expect(settings.codexProbeMode() == .api)
        }
    }

    // MARK: - #34: API mode credential status

    @Suite("Scenario: API mode credential availability")
    struct CredentialStatus {

        @Test
        func `supportsApiMode is false for RPC-only provider`() {
            // Given — single probe (RPC only)
            let settings = MockProviderSettingsRepository()
            given(settings).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
            given(settings).isEnabled(forProvider: .any).willReturn(true)
            given(settings).setEnabled(.any, forProvider: .any).willReturn()

            let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)

            // Then
            #expect(codex.supportsApiMode == false)
        }

        @Test
        func `supportsApiMode is true for dual-probe provider`() {
            // Given — dual probe setup
            let suiteName = "com.claudebar.test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            let settings = UserDefaultsProviderSettingsRepository(userDefaults: defaults)
            settings.setEnabled(true, forProvider: "codex")

            let codex = CodexProvider(
                rpcProbe: MockUsageProbe(),
                apiProbe: MockUsageProbe(),
                settingsRepository: settings
            )

            // Then
            #expect(codex.supportsApiMode == true)
        }
    }
}
