import Kit
import Foundation
import Testing
@testable import ClaudeBar

/// The words of Settings' Data source section, from a definition — so a
/// provider that is data needs no card of its own.
@Suite
struct DataSourceSectionTextTests {
    private static let kit = try! TestKit.start()
    private func codex() throws -> ProviderDefinition { try #require(Self.kit.definition(lineupId: "codex")) }
    private func claude() throws -> ProviderDefinition { try #require(Self.kit.definition(lineupId: "claude")) }

    @Test
    func `should title the data source section with the provider's name and that it is built in`() throws {
        let text = DataSourceSectionText(definition: try codex())

        #expect(text.title == "Codex Configuration")
        #expect(text.subtitle == "Data fetching method for all Codex accounts")
        #expect(text.origin == "Built in")
        #expect(DataSourceSectionText(definition: try claude()).subtitle == "Data fetching method for all Claude accounts")
    }

    @Test
    func `should offer only the data sources a person can pick`() throws {
        let text = DataSourceSectionText(definition: try codex())

        #expect(text.choices.map { $0.kind } == ["rpc", "api"])
        #expect(text.choices.map { $0.label } == ["RPC", "API"])
    }

    @Test
    func `should show where the key is looked for as a path through places`() throws {
        let text = DataSourceSectionText(definition: try claude())

        #expect(text.lookupOrder(for: "api") == "~/.claude/.credentials.json → Keychain “Claude Code-credentials” → $CLAUDE_CODE_OAUTH_TOKEN")
        #expect(text.lookupOrder(for: "cli") == nil)
    }

    @Test
    func `should say in one sentence what ClaudeBar tries when a data source is unavailable`() throws {
        #expect(DataSourceSectionText(definition: try claude()).fallback(for: "api") == "If API is unavailable, ClaudeBar tries CLI.")
        #expect(DataSourceSectionText(definition: try codex()).fallback(for: "rpc") == "If RPC is unavailable, ClaudeBar tries Terminal.")
        #expect(DataSourceSectionText(definition: try codex()).fallback(for: "api") == nil)
    }

    @Test
    func `should say background refresh is capped at 15 min while Claude's cached API is in use`() throws {
        #expect(DataSourceSectionText(definition: try claude()).cacheNote(for: "api")
            == "Usage data is cached for 15 min, so background refresh is capped at 15 min while API is in use.")
        #expect(DataSourceSectionText(definition: try claude()).cacheNote(for: "cli") == nil)
    }

    @Test
    func `should say what came back from a connection test, or which step failed`() {
        #expect(DataSourceSectionText.testResult(.success(Response(status: 200))) == "Connected · 200")
        #expect(DataSourceSectionText.testResult(.success(Response(text: "screen"))) == "Connected")
        #expect(DataSourceSectionText.testResult(.failure(DataSourceError(step: .lookup, reason: UsageError.AuthenticationRequired.shared)))
            .hasPrefix("Couldn't read your key · "))
    }

    @Test
    func `should say where a provider's CLI is found`() throws {
        let text = DataSourceSectionText(definition: try claude())

        #expect(text.cliLocation?.placeholder == "Found automatically: claude")
        #expect(text.cliLocation?.help.contains("Add Account") == true)
    }

    @Test
    func `should show no CLI location for a provider without a CLI`() throws {
        var draft = ProviderDraftForm(start: .api)
        draft.url = "https://example.test/usage"
        draft.key = .apiKey
        draft.measure = .percentUsed
        draft.used = "$.used"
        draft.name = "Example"

        let kit = try TestKit.start()
        let provider = try #require(try value(of: kit.workshop.add(draft: draft.draft, key: "")))
        #expect(DataSourceSectionText(definition: provider.definition).cliLocation == nil)
    }
}
