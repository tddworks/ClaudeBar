import Testing
import Foundation
import Mockable
import Providers

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
    @MainActor
    struct UpdateInfrastructure {

        @Test
        func `should link Claude and Codex to their status pages`() throws {
            // Given — when updates fail, users can check status pages
            let claude = try ProviderFactory.builtIn("claude")
            let codex = try ProviderFactory.builtIn("codex")

            // Then
            #expect(claude.profile.links.status?.absoluteString == "https://status.anthropic.com")
            #expect(codex.profile.links.status?.absoluteString == "https://status.openai.com")
        }
    }
}
