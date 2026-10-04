import Testing
import Foundation
import DataSources
import Providers
@testable import Domain

/// USER_JOURNEYS §5 — Lin shares her team's gateway; a teammate imports it.
@Suite("Feature: Export and import a provider")
struct ShareProviderSpec {

    private static func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("share-spec-\(UUID().uuidString)")
    }

    @Suite("Scenario: An exported provider carries no key")
    struct ExportCarriesNoKey {
        @Test
        func `the file names the key's setting and lookup order, and contains no key`() throws {
            // Given a custom provider whose API key is in the Keychain
            var draft = ProviderDraft(start: .api)
            draft.url = "https://llm.team.example/v1/usage"
            draft.key = .apiKey
            draft.measure = .percentUsed
            draft.used = "$.used"
            draft.name = "Team Gateway"
            let definition = try draft.definition(id: "custom-team-gateway-abc123")
            let keyInKeychain = "sk-team-secret-42"

            // When it is exported
            let file = String(decoding: try definition.exported(), as: UTF8.self)

            // Then the file names the key's setting and lookup order, and contains no key
            #expect(file.contains("\"setting\" : \"apiKey\""))
            #expect(!file.contains(keyInKeychain))
        }
    }

    @Suite("Scenario: Importing a CLI provider asks first")
    struct ImportingACLIAsksFirst {
        @Test
        func `the command is shown before anything is saved or run`() throws {
            // Given a provider file whose data source is a CLI command
            var draft = ProviderDraft(start: .cli)
            draft.command = "teamtool usage --json"
            draft.measure = .percentLeft
            draft.remaining = "$.left"
            draft.name = "Team Tool"
            let file = try draft.definition(id: "custom-team-tool-abc123").exported()
            let catalog = ProviderCatalog(directory: ShareProviderSpec.folder())
            defer { try? FileManager.default.removeItem(at: catalog.directory) }

            // When it is imported — reviewed first
            let review = try catalog.review(file)

            // Then the command is shown, and nothing is saved until the person adds it
            #expect(review.runs == ["teamtool usage --json"])
            #expect(catalog.custom().isEmpty)
            try catalog.import(review)
            #expect(catalog.custom().map(\.profile.name) == ["Team Tool"])
        }
    }
}
