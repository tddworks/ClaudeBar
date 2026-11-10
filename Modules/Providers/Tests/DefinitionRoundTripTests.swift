import DataSources
import Foundation
import Providers
import Testing

/// An account runs a built-in data source re-read through JSON — filled with
/// its values. Anything lost on the way would silently change what it fetches.
@Suite
struct DefinitionRoundTripTests {
    @Test(arguments: ["claude", "codex", "deepseek", "minimax", "vercel-gateway", "runcrate", "uberllm", "commandcode", "ampcode", "kiro", "cursor", "grok", "opencode-go", "zai", "kimi", "copilot", "alibaba", "gemini", "antigravity", "bedrock", "omp", "mistral"])
    func `should fetch the same way when a built-in data source is written out and read back`(_ id: String) throws {
        let definition = try ProviderFactory.builtIn(id)

        for source in definition.dataSources {
            let again = try JSONDecoder().decode(DataSourceDefinition.self, from: JSONEncoder().encode(source))
            #expect(again == source, "\(id).\(source.kind) changed on the round trip")
        }
    }

    @Test
    func `should leave a data source unchanged when it is filled with no values`() throws {
        let codex = try ProviderFactory.builtIn("codex")

        for source in codex.dataSources {
            #expect(try source.filled([:], scope: "account") == source)
        }
    }
}
