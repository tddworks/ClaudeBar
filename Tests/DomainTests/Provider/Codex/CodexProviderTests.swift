import Testing
import Foundation
import Mockable
@testable import Domain

@Suite("CodexProvider Tests")
@MainActor
struct CodexProviderTests {

    private func makeSettingsRepository() -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(mock).isEnabled(forProvider: .any).willReturn(true)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        return mock
    }

    // MARK: - Identity

    @Test
    func `codex provider has correct id`() {
        let settings = makeSettingsRepository()
        let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(codex.id == "codex")
    }

    @Test
    func `codex provider has correct name`() {
        let settings = makeSettingsRepository()
        let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(codex.name == "Codex")
    }

    @Test
    func `codex provider has correct cliCommand`() {
        let settings = makeSettingsRepository()
        let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(codex.cliCommand == "codex")
    }

    @Test
    func `codex provider has dashboard URL pointing to openai`() {
        let settings = makeSettingsRepository()
        let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(codex.dashboardURL != nil)
        #expect(codex.dashboardURL?.host?.contains("openai") == true)
    }

    @Test
    func `codex provider is enabled by default`() {
        let settings = makeSettingsRepository()
        let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
        #expect(codex.isEnabled == true)
    }
}
