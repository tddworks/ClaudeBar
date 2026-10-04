import DataSources
import Domain
import Foundation
import Providers
import Testing
@testable import ClaudeBar

/// The words of Settings' Data source section, from a definition — so a
/// provider that is data needs no card of its own.
@Suite
struct DataSourceSectionTextTests {
    private func codex() throws -> ProviderDefinition { try Providers.builtIn("codex") }
    private func claude() throws -> ProviderDefinition { try Providers.builtIn("claude") }

    @Test
    func `the header names the product and its origin`() throws {
        let text = DataSourceSectionText(definition: try codex())

        #expect(text.title == "Codex Configuration")
        #expect(text.subtitle == "Data fetching method for all Codex accounts")
        #expect(text.origin == "Built in")
        #expect(DataSourceSectionText(definition: try claude()).subtitle == "Data fetching method for all Claude accounts")
    }

    @Test
    func `only the data sources a person can pick are offered`() throws {
        let text = DataSourceSectionText(definition: try codex())

        #expect(text.choices.map(\.kind) == ["rpc", "api"])
        #expect(text.choices.map(\.label) == ["RPC", "API"])
    }

    @Test
    func `the key lookup order reads as a path through places`() throws {
        let text = DataSourceSectionText(definition: try claude())

        #expect(text.lookupOrder(for: "api") == "~/.claude/.credentials.json → Keychain “Claude Code-credentials” → $CLAUDE_CODE_OAUTH_TOKEN")
        #expect(text.lookupOrder(for: "cli") == nil)
    }

    @Test
    func `the fallback is one sentence`() throws {
        #expect(DataSourceSectionText(definition: try claude()).fallback(for: "api") == "If API is unavailable, ClaudeBar tries CLI.")
        #expect(DataSourceSectionText(definition: try codex()).fallback(for: "rpc") == "If RPC is unavailable, ClaudeBar tries Terminal.")
        #expect(DataSourceSectionText(definition: try codex()).fallback(for: "api") == nil)
    }

    @Test
    func `a cached data source says what that does to background refresh`() throws {
        #expect(DataSourceSectionText(definition: try claude()).cacheNote(for: "api")
            == "Usage data is cached for 15 min, so background refresh is capped at 15 min while API is in use.")
        #expect(DataSourceSectionText(definition: try claude()).cacheNote(for: "cli") == nil)
    }

    @Test
    func `a test connection says what came back, or which step failed`() {
        #expect(DataSourceSectionText.testResult(.success(Response(status: 200, body: Data()))) == "Connected · 200")
        #expect(DataSourceSectionText.testResult(.success(Response(text: "screen"))) == "Connected")
        #expect(DataSourceSectionText.testResult(.failure(DataSourceError(.lookup, .authenticationRequired)))
            .hasPrefix("Couldn't read your key · "))
    }

    @Test
    func `a provider that runs a cli says where it finds it`() throws {
        let text = DataSourceSectionText(definition: try claude())

        #expect(text.cliLocation?.placeholder == "Found automatically: claude")
        #expect(text.cliLocation?.help.contains("Add Account") == true)
    }

    @Test
    func `a provider without a cli has no cli location`() throws {
        var draft = ProviderDraft(start: .api)
        draft.url = "https://example.test/usage"
        draft.key = .apiKey
        draft.measure = .percentUsed
        draft.used = "$.used"
        draft.name = "Example"

        #expect(DataSourceSectionText(definition: try draft.definition(id: "custom-example")).cliLocation == nil)
    }
}
