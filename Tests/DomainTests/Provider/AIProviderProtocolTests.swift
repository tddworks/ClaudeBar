import Testing
import Foundation
import Mockable
@testable import Domain

@Suite
struct AIProviderProtocolTests {

    /// Creates a mock settings repository that returns true for all providers
    private func makeSettingsRepository() -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(mock).isEnabled(forProvider: .any).willReturn(true)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        return mock
    }

    // MARK: - Protocol Conformance

    @Test
    func `provider has required id property`() {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let claude = ClaudeProvider(probe: mockProbe, settingsRepository: settings)

        #expect(claude.id == "claude")
    }

    @Test
    func `provider has required name property`() {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let claude = ClaudeProvider(probe: mockProbe, settingsRepository: settings)

        #expect(claude.name == "Claude")
    }

    @Test
    func `provider has required cliCommand property`() {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let claude = ClaudeProvider(probe: mockProbe, settingsRepository: settings)

        #expect(claude.cliCommand == "claude")
    }

    @Test
    func `provider has dashboardURL property`() {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let claude = ClaudeProvider(probe: mockProbe, settingsRepository: settings)

        #expect(claude.dashboardURL != nil)
        #expect(claude.dashboardURL?.absoluteString.contains("anthropic.com") == true)
    }

    @Test
    func `provider delegates isAvailable to probe`() async {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).isAvailable().willReturn(true)
        let claude = ClaudeProvider(probe: mockProbe, settingsRepository: settings)

        let isAvailable = await claude.isAvailable()

        #expect(isAvailable == true)
    }

    @Test
    func `provider delegates refresh to probe`() async throws {
        let settings = makeSettingsRepository()
        let expectedSnapshot = UsageSnapshot(
            providerId: "claude",
            quotas: [],
            capturedAt: Date()
        )
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(expectedSnapshot)
        let claude = ClaudeProvider(probe: mockProbe, settingsRepository: settings)

        let snapshot = try await claude.refresh()

        #expect(snapshot.quotas.isEmpty)
    }

    // MARK: - Equality via ID

    @Test
    func `providers with same id are equal`() {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let provider1 = ClaudeProvider(probe: mockProbe, settingsRepository: settings)
        let provider2 = ClaudeProvider(probe: mockProbe, settingsRepository: settings)

        #expect(provider1.id == provider2.id)
    }

    @Test
    func `different providers have different ids`() {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let claude = ClaudeProvider(probe: mockProbe, settingsRepository: settings)
        let codex = CodexProvider(probe: mockProbe, settingsRepository: settings)
        let gemini = GeminiProvider(probe: mockProbe, settingsRepository: settings)

        #expect(claude.id != codex.id)
        #expect(claude.id != gemini.id)
        #expect(codex.id != gemini.id)
    }

    // MARK: - Provider State

    @Test
    func `provider tracks isSyncing state during refresh`() async throws {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(UsageSnapshot(
            providerId: "claude",
            quotas: [],
            capturedAt: Date()
        ))
        let claude = ClaudeProvider(probe: mockProbe, settingsRepository: settings)

        #expect(claude.isSyncing == false)

        _ = try await claude.refresh()

        // After refresh completes, isSyncing should be false again
        #expect(claude.isSyncing == false)
    }

    @Test
    func `provider stores snapshot after refresh`() async throws {
        let settings = makeSettingsRepository()
        let expectedSnapshot = UsageSnapshot(
            providerId: "claude",
            quotas: [UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "claude")],
            capturedAt: Date()
        )
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(expectedSnapshot)
        let claude = ClaudeProvider(probe: mockProbe, settingsRepository: settings)

        #expect(claude.snapshot == nil)

        _ = try await claude.refresh()

        #expect(claude.snapshot != nil)
        #expect(claude.snapshot?.quotas.first?.percentRemaining == 50)
    }

    @Test
    func `provider stores error on refresh failure`() async {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willThrow(ProbeError.timeout)
        let claude = ClaudeProvider(probe: mockProbe, settingsRepository: settings)

        #expect(claude.lastError == nil)

        do {
            _ = try await claude.refresh()
        } catch {
            // Expected to throw
        }

        #expect(claude.lastError != nil)
    }
}

// MARK: - Provider Identity Tests

@Suite
struct ProviderIdentityTests {

    /// Creates a mock settings repository that returns true for all providers
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
        #expect(ids.count == 3)
    }

    @Test
    func `all providers have display names`() {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let gemini = GeminiProvider(probe: MockUsageProbe(), settingsRepository: settings)

        #expect(claude.name == "Claude")
        #expect(codex.name == "Codex")
        #expect(gemini.name == "Gemini")
    }

    @Test
    func `provider name matches its identity`() {
        // This tests the rich domain model - name is from provider, not hardcoded
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)

        #expect(claude.id == "claude")
        #expect(claude.name == "Claude")
        #expect(claude.cliCommand == "claude")
    }

    @Test
    func `codex provider has correct identity`() {
        let settings = makeSettingsRepository()
        let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)

        #expect(codex.id == "codex")
        #expect(codex.name == "Codex")
        #expect(codex.cliCommand == "codex")
    }

    @Test
    func `gemini provider has correct identity`() {
        let settings = makeSettingsRepository()
        let gemini = GeminiProvider(probe: MockUsageProbe(), settingsRepository: settings)

        #expect(gemini.id == "gemini")
        #expect(gemini.name == "Gemini")
        #expect(gemini.cliCommand == "gemini")
    }

    @Test
    func `all providers have dashboard urls`() {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let gemini = GeminiProvider(probe: MockUsageProbe(), settingsRepository: settings)

        #expect(claude.dashboardURL != nil)
        #expect(codex.dashboardURL != nil)
        #expect(gemini.dashboardURL != nil)
    }

    @Test
    func `claude dashboard url points to anthropic`() {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)

        #expect(claude.dashboardURL?.host?.contains("anthropic") == true)
    }

    @Test
    func `codex dashboard url points to openai`() {
        let settings = makeSettingsRepository()
        let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)

        #expect(codex.dashboardURL?.host?.contains("openai") == true)
    }

    @Test
    func `gemini dashboard url points to google`() {
        let settings = makeSettingsRepository()
        let gemini = GeminiProvider(probe: MockUsageProbe(), settingsRepository: settings)

        #expect(gemini.dashboardURL?.host?.contains("google") == true)
    }

    @Test
    func `providers are enabled by default`() {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
        let gemini = GeminiProvider(probe: MockUsageProbe(), settingsRepository: settings)

        #expect(claude.isEnabled == true)
        #expect(codex.isEnabled == true)
        #expect(gemini.isEnabled == true)
    }
}
