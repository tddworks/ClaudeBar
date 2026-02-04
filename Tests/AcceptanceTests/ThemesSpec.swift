import Testing
import Foundation
@testable import Domain
@testable import Infrastructure

/// Feature: Themes
///
/// Users select visual themes from Settings.
///
/// Behaviors covered:
/// - #49: User selects Dark/Light/CLI/Christmas theme → UI updates immediately
/// - #50: System theme follows macOS light/dark mode
/// - #51: Christmas theme auto-enables Dec 24–26, reverts after
///
/// Note: Theme types (ThemeMode, ThemeRegistry) are in the App layer,
/// which is not accessible from this test target. These scenarios would
/// need App-layer tests or moving theme types to Domain.
/// For now, we test the domain-level aspects that support theming.
@Suite("Feature: Themes")
struct ThemesSpec {

    // MARK: - #49: Each provider has distinct identity for themed display

    @Suite("Scenario: Provider identity for themed display")
    struct ProviderIdentity {

        private static func makeSettings() -> MockProviderSettingsRepository {
            let mock = MockProviderSettingsRepository()
            given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
            given(mock).isEnabled(forProvider: .any).willReturn(true)
            given(mock).setEnabled(.any, forProvider: .any).willReturn()
            return mock
        }

        @Test
        func `each provider has unique id and display name`() {
            // Given — all providers
            let settings = Self.makeSettings()
            let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
            let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)

            // Then — unique identities for theme mapping
            #expect(claude.id == "claude")
            #expect(claude.name == "Claude")
            #expect(codex.id == "codex")
            #expect(codex.name == "Codex")
            #expect(claude.id != codex.id)
        }
    }
}
