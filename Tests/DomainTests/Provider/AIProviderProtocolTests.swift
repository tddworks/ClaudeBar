import Testing
import Foundation
import Mockable
@testable import Domain

/// Cross-provider tests that verify the AIProvider protocol contract across all providers.
@Suite("AIProvider Cross-Provider Tests")
@MainActor
struct AIProviderProtocolTests {

    private func makeSettingsRepository() -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(mock).isEnabled(forProvider: .any).willReturn(true)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        return mock
    }

    @Test
    func `all providers have unique ids`() {
        let settings = makeSettingsRepository()
        let providers: [any AIProvider] = [
            ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings),
            CodexProvider(probe: MockUsageProbe(), settingsRepository: settings),
            GeminiProvider(probe: MockUsageProbe(), settingsRepository: settings)
        ]

        let ids = Set(providers.map(\.id))
        #expect(ids.count == providers.count)
    }

    @Test
    func `all providers have display names`() {
        let settings = makeSettingsRepository()
        let providers: [any AIProvider] = [
            ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings),
            CodexProvider(probe: MockUsageProbe(), settingsRepository: settings),
            GeminiProvider(probe: MockUsageProbe(), settingsRepository: settings)
        ]

        for provider in providers {
            #expect(!provider.name.isEmpty)
        }
    }

    @Test
    func `all providers have dashboard urls`() {
        let settings = makeSettingsRepository()
        let providers: [any AIProvider] = [
            ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings),
            CodexProvider(probe: MockUsageProbe(), settingsRepository: settings),
            GeminiProvider(probe: MockUsageProbe(), settingsRepository: settings)
        ]

        for provider in providers {
            #expect(provider.dashboardURL != nil)
        }
    }

    @Test
    func `different providers have different ids`() {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let gemini = GeminiProvider(probe: MockUsageProbe(), settingsRepository: settings)

        #expect(claude.id != codex.id)
        #expect(claude.id != gemini.id)
        #expect(codex.id != gemini.id)
    }
}
