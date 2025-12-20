import Testing
@testable import Domain

@Suite("AI Provider Tests")
struct AIProviderTests {

    // MARK: - Provider Identity

    @Test("Claude provider has correct identity")
    func claudeProviderIdentity() {
        let provider = AIProvider.claude

        #expect(provider.name == "Claude")
        #expect(provider.cliCommand == "claude")
        #expect(provider.isEnabled == true)
    }

    @Test("Codex provider has correct identity")
    func codexProviderIdentity() {
        let provider = AIProvider.codex

        #expect(provider.name == "Codex")
        #expect(provider.cliCommand == "codex")
        #expect(provider.isEnabled == true)
    }

    @Test("Gemini provider has correct identity")
    func geminiProviderIdentity() {
        let provider = AIProvider.gemini

        #expect(provider.name == "Gemini")
        #expect(provider.cliCommand == "gemini")
        #expect(provider.isEnabled == true)
    }

    @Test("All providers are enumerable")
    func allProvidersEnumerable() {
        let allProviders = AIProvider.allCases

        #expect(allProviders.count == 3)
        #expect(allProviders.contains(.claude))
        #expect(allProviders.contains(.codex))
        #expect(allProviders.contains(.gemini))
    }

    // MARK: - Provider Dashboard Links

    @Test("Claude has dashboard URL")
    func claudeDashboardURL() {
        let provider = AIProvider.claude

        #expect(provider.dashboardURL?.absoluteString == "https://console.anthropic.com/settings/billing")
    }

    @Test("Codex has dashboard URL")
    func codexDashboardURL() {
        let provider = AIProvider.codex

        #expect(provider.dashboardURL?.absoluteString == "https://chatgpt.com/codex/settings/usage")
    }
}
