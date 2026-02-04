import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

/// Feature: Updates
///
/// Users manage app updates and beta channel preferences.
///
/// Behaviors covered:
/// - #52: App checks for updates when menu opens
/// - #53: User toggles beta channel → receives pre-release updates
/// - #54: User clicks manual check → shows available version or "up to date"
///
/// Note: Update logic (Sparkle, AppSettings) lives in the App layer,
/// which is not accessible from this test target. These scenarios
/// are partially covered by existing update channel tests in DomainTests.
/// Full acceptance testing would require App-layer test target.
@Suite("Feature: Updates")
struct UpdatesSpec {

    // MARK: - Placeholder for App-layer update tests

    @Suite("Scenario: Update infrastructure")
    struct UpdateInfrastructure {

        @Test
        func `providers expose status page URLs for fallback`() {
            // Given — when updates fail, users can check status pages
            let settings = MockProviderSettingsRepository()
            given(settings).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
            given(settings).isEnabled(forProvider: .any).willReturn(true)
            given(settings).setEnabled(.any, forProvider: .any).willReturn()

            let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
            let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)

            // Then
            #expect(claude.statusPageURL?.absoluteString == "https://status.anthropic.com")
            #expect(codex.statusPageURL?.absoluteString == "https://status.openai.com")
        }
    }
}
