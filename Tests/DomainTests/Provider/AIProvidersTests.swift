import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

@Suite
@MainActor
struct AIProvidersTests {

    /// Creates a mock settings repository that returns true for all providers
    private func makeSettingsRepository() -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(mock).isEnabled(forProvider: .any).willReturn(true)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        return mock
    }

    // MARK: - All Providers

    @Test
    func `all returns all registered providers`() {
        let settings = makeSettingsRepository()
        let providers = AIProviders(providers: [
            ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings),
            CodexProvider(probe: MockUsageProbe(), settingsRepository: settings),
            GeminiProvider(probe: MockUsageProbe(), settingsRepository: settings)
        ])

        #expect(providers.all.count == 3)
    }

    @Test
    func `all returns empty when no providers registered`() {
        let providers = AIProviders(providers: [])

        #expect(providers.all.isEmpty)
    }

    // MARK: - Enabled Providers

    @Test
    func `enabled returns only providers with isEnabled true`() {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let gemini = GeminiProvider(probe: MockUsageProbe(), settingsRepository: settings)

        // Disable gemini
        gemini.isEnabled = false

        let providers = AIProviders(providers: [claude, codex, gemini])

        #expect(providers.enabled.count == 2)
        #expect(providers.enabled.contains { $0.id == "claude" })
        #expect(providers.enabled.contains { $0.id == "codex" })
        #expect(!providers.enabled.contains { $0.id == "gemini" })
    }

    @Test
    func `enabled returns empty when all providers disabled`() {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)

        claude.isEnabled = false
        codex.isEnabled = false

        let providers = AIProviders(providers: [claude, codex])

        #expect(providers.enabled.isEmpty)
    }

    @Test
    func `enabled returns all when all providers enabled`() {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)

        // Both enabled by default
        let providers = AIProviders(providers: [claude, codex])

        #expect(providers.enabled.count == 2)
    }

    // MARK: - Lookup

    @Test
    func `provider by id returns correct provider`() {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)

        let providers = AIProviders(providers: [claude, codex])

        #expect(providers.provider(id: "claude")?.name == "Claude")
        #expect(providers.provider(id: "codex")?.name == "Codex")
    }

    @Test
    func `provider by id returns nil for unknown id`() {
        let settings = makeSettingsRepository()
        let providers = AIProviders(providers: [
            ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        ])

        #expect(providers.provider(id: "unknown") == nil)
    }

    // MARK: - Toggle Enabled State

    @Test
    func `toggling provider isEnabled updates enabled list`() {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let providers = AIProviders(providers: [claude])

        #expect(providers.enabled.count == 1)

        claude.isEnabled = false

        #expect(providers.enabled.isEmpty)

        claude.isEnabled = true

        #expect(providers.enabled.count == 1)
    }

    // MARK: - Add Provider

    @Test
    func `add appends new provider to all`() {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let providers = AIProviders(providers: [claude])

        #expect(providers.all.count == 1)

        let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
        providers.add(codex)

        #expect(providers.all.count == 2)
        #expect(providers.all.contains { $0.id == "codex" })
    }

    @Test
    func `add does not duplicate existing provider`() {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let providers = AIProviders(providers: [claude])

        let anotherClaude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        providers.add(anotherClaude)

        #expect(providers.all.count == 1)
    }

    @Test
    func `add to empty repository works`() {
        let settings = makeSettingsRepository()
        let providers = AIProviders(providers: [])

        #expect(providers.all.isEmpty)

        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        providers.add(claude)

        #expect(providers.all.count == 1)
        #expect(providers.all.first?.id == "claude")
    }

    // MARK: - Remove Provider

    @Test
    func `remove deletes provider by id`() {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let providers = AIProviders(providers: [claude, codex])

        #expect(providers.all.count == 2)

        providers.remove(id: "claude")

        #expect(providers.all.count == 1)
        #expect(providers.all.first?.id == "codex")
    }

    @Test
    func `remove does nothing for unknown id`() {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let providers = AIProviders(providers: [claude])

        providers.remove(id: "unknown")

        #expect(providers.all.count == 1)
    }

    @Test
    func `remove from empty repository does nothing`() {
        let providers = AIProviders(providers: [])

        providers.remove(id: "claude")

        #expect(providers.all.isEmpty)
    }
}
