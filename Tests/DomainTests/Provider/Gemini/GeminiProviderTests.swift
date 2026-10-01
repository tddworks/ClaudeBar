import Testing
import Foundation
import Mockable
@testable import Domain

@Suite("GeminiProvider Tests")
@MainActor
struct GeminiProviderTests {

    private func makeSettingsRepository() -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(mock).isEnabled(forProvider: .any).willReturn(true)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        return mock
    }

    // MARK: - Identity

    @Test
    func `gemini provider has correct id`() {
        let settings = makeSettingsRepository()
        let gemini = GeminiProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(gemini.id == "gemini")
    }

    @Test
    func `gemini provider has correct name`() {
        let settings = makeSettingsRepository()
        let gemini = GeminiProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(gemini.name == "Gemini")
    }

    @Test
    func `gemini provider has correct cliCommand`() {
        let settings = makeSettingsRepository()
        let gemini = GeminiProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(gemini.cliCommand == "gemini")
    }

    @Test
    func `gemini provider has dashboard URL pointing to google`() {
        let settings = makeSettingsRepository()
        let gemini = GeminiProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(gemini.dashboardURL != nil)
        #expect(gemini.dashboardURL?.host?.contains("google") == true)
    }

    @Test
    func `gemini provider is enabled by default`() {
        let settings = makeSettingsRepository()
        let gemini = GeminiProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(gemini.isEnabled == true)
    }
}
