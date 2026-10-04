import DataSources
import Foundation
import Providers
import Testing

/// An added login runs a built-in data source re-read through JSON — patched
/// and filled. Anything lost on the way would silently change what it fetches.
@Suite
struct DefinitionRoundTripTests {
    @Test(arguments: ["claude", "codex", "deepseek", "minimax", "vercel-gateway", "commandcode", "ampcode", "kiro", "cursor", "grok", "opencode-go", "zai", "kimi", "copilot", "alibaba", "gemini", "antigravity", "bedrock", "omp", "mistral"])
    func `every built-in data source survives being written out and read back`(_ id: String) throws {
        let definition = try Providers.builtIn(id)

        for source in definition.dataSources {
            let again = try JSONDecoder().decode(DataSourceDefinition.self, from: JSONEncoder().encode(source))
            #expect(again == source, "\(id).\(source.kind) changed on the round trip")
        }
    }

    @Test
    func `an empty patch and no values leave a data source as it was`() throws {
        let codex = try Providers.builtIn("codex")

        for source in codex.dataSources {
            #expect(try source.patched(with: .object([:])).filled([:], scope: "account") == source)
        }
    }
}
