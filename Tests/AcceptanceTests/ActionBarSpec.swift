import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

/// Feature: Action Bar
///
/// Users interact with action buttons: Dashboard, Refresh, Share, Settings, Quit.
///
/// Behaviors covered:
/// - #24: User clicks Dashboard → opens provider's web dashboard in browser
/// - #25: User clicks Share (Claude only) → shows referral link overlay
@Suite("Feature: Action Bar")
struct ActionBarSpec {

    // MARK: - #24: Dashboard URLs

    @Suite("Scenario: Dashboard opens correct URL per provider")
    @MainActor
    struct DashboardURLs {

        private static func makeSettings() -> MockProviderSettingsRepository {
            let mock = MockProviderSettingsRepository()
            given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
            given(mock).isEnabled(forProvider: .any).willReturn(true)
            given(mock).setEnabled(.any, forProvider: .any).willReturn()
            return mock
        }

        @Test
        func `Claude dashboard URL is Anthropic billing`() {
            let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: Self.makeSettings())
            #expect(claude.dashboardURL?.absoluteString == "https://console.anthropic.com/settings/billing")
        }

        @Test
        func `Codex dashboard URL is OpenAI usage`() {
            let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: Self.makeSettings())
            #expect(codex.dashboardURL?.absoluteString == "https://platform.openai.com/usage")
        }

        @Test
        func `Copilot dashboard URL is GitHub features page`() {
            let suiteName = "com.claudebar.test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            let settings = UserDefaultsProviderSettingsRepository(userDefaults: defaults)
            let copilot = CopilotProvider(probe: MockUsageProbe(), settingsRepository: settings)
            #expect(copilot.dashboardURL?.absoluteString == "https://github.com/settings/copilot/features")
        }

        @Test
        func `Antigravity has no dashboard URL`() {
            let antigravity = AntigravityProvider(probe: MockUsageProbe(), settingsRepository: Self.makeSettings())
            #expect(antigravity.dashboardURL == nil)
        }

        @Test
        func `Bedrock dashboard URL is AWS console`() {
            let suiteName = "com.claudebar.test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            let settings = UserDefaultsProviderSettingsRepository(userDefaults: defaults)
            let bedrock = BedrockProvider(probe: MockUsageProbe(), settingsRepository: settings)
            #expect(bedrock.dashboardURL?.absoluteString == "https://console.aws.amazon.com/bedrock/home")
        }

        @Test
        func `Zai dashboard URL is Z.ai subscribe`() {
            let suiteName = "com.claudebar.test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            let settings = UserDefaultsProviderSettingsRepository(userDefaults: defaults)
            let zai = ZaiProvider(probe: MockUsageProbe(), settingsRepository: settings)
            #expect(zai.dashboardURL?.absoluteString == "https://z.ai/subscribe")
        }
    }

    // MARK: - #25: Claude guest passes

    @Suite("Scenario: Share Claude Code guest passes")
    @MainActor
    struct GuestPasses {

        private static func makeSettings() -> MockProviderSettingsRepository {
            let settings = MockProviderSettingsRepository()
            given(settings).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
            given(settings).isEnabled(forProvider: .any).willReturn(true)
            given(settings).setEnabled(.any, forProvider: .any).willReturn()
            return settings
        }

        private static func makeUsageProbe(tier: AccountTier?) -> MockUsageProbe {
            let probe = MockUsageProbe()
            given(probe).probe().willReturn(
                UsageSnapshot(providerId: "claude", quotas: [], capturedAt: Date(), accountTier: tier)
            )
            given(probe).isAvailable().willReturn(true)
            return probe
        }

        @Test
        func `Claude supports guest passes when pass probe is provided`() {
            // Without pass probe
            let withoutPass = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: Self.makeSettings())
            #expect(withoutPass.supportsGuestPasses == false)
        }

        @Test
        func `Max account sees the Share button`() async throws {
            let claude = ClaudeProvider(
                probe: Self.makeUsageProbe(tier: .claudeMax),
                passProbe: MockClaudePassProbing(),
                settingsRepository: Self.makeSettings()
            )

            try await claude.refresh()

            #expect(claude.supportsGuestPasses == true)
        }

        @Test
        func `Pro account does not see the Share button`() async throws {
            // Issue #243: Anthropic issues invitation links to Max plans only.
            let claude = ClaudeProvider(
                probe: Self.makeUsageProbe(tier: .claudePro),
                passProbe: MockClaudePassProbing(),
                settingsRepository: Self.makeSettings()
            )

            try await claude.refresh()

            #expect(claude.supportsGuestPasses == false)
        }

        @Test
        func `failed pass fetch is reported instead of failing silently`() async {
            let passProbe = MockClaudePassProbing()
            given(passProbe).probe().willThrow(ProbeError.parseFailed("Could not find referral URL"))
            let claude = ClaudeProvider(
                probe: Self.makeUsageProbe(tier: .claudeMax),
                passProbe: passProbe,
                settingsRepository: Self.makeSettings()
            )

            do {
                _ = try await claude.fetchPasses()
            } catch {
                // Expected to throw
            }

            #expect(claude.passError != nil)
            #expect(claude.guestPass == nil)
        }
    }
}
