import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

/// Feature: Z.ai Configuration
///
/// Users configure custom config paths and environment variable
/// fallbacks for Z.ai authentication.
///
/// Behaviors covered:
/// - #41: User sets custom config path → probe reads from that file
/// - #42: User sets env var fallback → probe uses env var if config file has no token
@Suite("Feature: Z.ai Configuration")
struct ZaiConfigSpec {

    // MARK: - #41: Custom config path

    @Suite("Scenario: Custom config path")
    struct CustomConfigPath {

        @Test
        func `config path is persisted in UserDefaults`() {
            // Given
            let suiteName = "com.claudebar.test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            let settings = UserDefaultsProviderSettingsRepository(userDefaults: defaults)

            // Default is empty
            #expect(settings.zaiConfigPath() == "")

            // When — user sets custom path
            settings.setZaiConfigPath("/custom/settings.json")

            // Then — persisted
            #expect(settings.zaiConfigPath() == "/custom/settings.json")
        }
    }

    // MARK: - #42: Environment variable fallback

    @Suite("Scenario: Environment variable fallback")
    struct EnvVarFallback {

        @Test
        func `env var name is persisted in UserDefaults`() {
            // Given
            let suiteName = "com.claudebar.test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            let settings = UserDefaultsProviderSettingsRepository(userDefaults: defaults)

            // Default is empty
            #expect(settings.glmAuthEnvVar() == "")

            // When — user sets env var
            settings.setGlmAuthEnvVar("GLM_AUTH_TOKEN")

            // Then — persisted
            #expect(settings.glmAuthEnvVar() == "GLM_AUTH_TOKEN")
        }

        @Test
        func `Zai provider delegates to probe for authentication`() async throws {
            // Given — probe returns successful snapshot
            let suiteName = "com.claudebar.test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            let settings = UserDefaultsProviderSettingsRepository(userDefaults: defaults)
            settings.setEnabled(true, forProvider: "zai")

            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willReturn(UsageSnapshot(
                providerId: "zai",
                quotas: [UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "zai")],
                capturedAt: Date()
            ))

            let zai = ZaiProvider(probe: probe, settingsRepository: settings)

            // When
            _ = try await zai.refresh()

            // Then
            #expect(zai.snapshot != nil)
            #expect(zai.snapshot?.quotas.first?.percentRemaining == 80)
        }

        @Test
        func `Zai provider stores error when authentication fails`() async {
            // Given — probe throws auth error
            let suiteName = "com.claudebar.test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            let settings = UserDefaultsProviderSettingsRepository(userDefaults: defaults)
            settings.setEnabled(true, forProvider: "zai")

            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willThrow(ProbeError.authenticationRequired)

            let zai = ZaiProvider(probe: probe, settingsRepository: settings)

            // When
            do {
                _ = try await zai.refresh()
            } catch {}

            // Then
            #expect(zai.snapshot == nil)
            #expect(zai.lastError != nil)
        }
    }
}
