import DataSources
import Foundation
import Providers
import Testing

/// *Export…* and *Import provider* (USER_JOURNEYS moments 10–11): a shared
/// file carries the key's NAME, never its value (F9); importing says where a
/// key will be sent and shows every command before anything is saved (F10).
@Suite
struct SharingTests {
    private func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("sharing-\(UUID().uuidString)")
    }

    private func gateway(id: String = "custom-team-gateway-1a2b3c") throws -> ProviderDefinition {
        var draft = ProviderDraft(start: .api)
        draft.url = "https://llm.example.com/v1/usage"
        draft.key = .apiKey
        draft.measure = .money(currency: "USD")
        draft.remaining = "$.remaining"
        draft.limit = "$.limit"
        draft.name = "Team Gateway"
        return try draft.definition(id: id)
    }

    private func tool() throws -> ProviderDefinition {
        var draft = ProviderDraft(start: .cli)
        draft.command = "teamtool usage --json"
        draft.measure = .percentLeft
        draft.remaining = "$.left"
        draft.name = "Team Tool"
        return try draft.definition(id: "custom-team-tool-9f8e7d")
    }

    @Test
    func `an exported provider names its key and holds no key`() throws {
        let file = String(decoding: try gateway().exported(), as: UTF8.self)

        #expect(file.contains("\"setting\" : \"apiKey\""))
        #expect(!file.contains("origin"))
        #expect(!file.contains("sk-"))
    }

    @Test
    func `an import says where the key will be sent and what it needs`() throws {
        let review = try ProviderCatalog(directory: folder()).review(try gateway().exported())

        #expect(review.definition.profile.name == "Team Gateway")
        #expect(review.definition.profile.origin == .custom)
        #expect(review.sendsKeyTo == ["llm.example.com"])
        #expect(review.runs.isEmpty)
        #expect(review.needs == ["apiKey"])
    }

    @Test
    func `an import of a CLI provider shows its command first`() throws {
        let review = try ProviderCatalog(directory: folder()).review(try tool().exported())

        #expect(review.runs == ["teamtool usage --json"])
        #expect(review.sendsKeyTo.isEmpty)
        #expect(review.needs.isEmpty)
    }

    @Test
    func `an import keeps its id unless it is taken`() throws {
        let catalog = ProviderCatalog(directory: folder())
        defer { try? FileManager.default.removeItem(at: catalog.directory) }
        let gateway = try gateway()

        let fresh = try catalog.review(try gateway.exported())
        try catalog.add(gateway)
        let again = try catalog.review(try gateway.exported())
        let builtIn = try catalog.review(try Providers.builtIn("codex").exported())

        #expect(fresh.definition.id == gateway.id)
        #expect(again.definition.id != gateway.id)
        #expect(again.definition.id.hasPrefix("custom-team-gateway-"))
        #expect(builtIn.definition.id != "codex")
        #expect(builtIn.definition.profile.origin == .custom)
    }

    @Test
    func `an imported provider is saved as custom`() throws {
        let catalog = ProviderCatalog(directory: folder())
        defer { try? FileManager.default.removeItem(at: catalog.directory) }

        let saved = try catalog.import(try catalog.review(try gateway().exported()))

        #expect(catalog.custom().map(\.id) == [saved.id])
        #expect(saved.dataSources == (try gateway()).dataSources)
    }

    @Test
    func `a file that isn't a provider is refused`() {
        #expect(throws: (any Error).self) { try ProviderCatalog(directory: folder()).review(Data("{}".utf8)) }
    }
}
