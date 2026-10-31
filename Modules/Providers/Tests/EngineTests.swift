import DataSources
import Foundation
import Mockable
import Providers
import Quotas
import Testing

/// The engine — everything that touches this Mac, built once and the same for
/// every provider (TARGET_ARCHITECTURE §10). A definition uses only what its
/// cases ask for; a capability is run for whichever definition declares it.
@MainActor @Suite
struct EngineTests {
    final class Count: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        private var clis: [String] = []
        func add() { lock.lock(); value += 1; lock.unlock() }
        func ran(_ cli: String) { lock.lock(); clis.append(cli); lock.unlock() }
        var times: Int { lock.lock(); defer { lock.unlock() }; return value }
        var cli: String? { lock.lock(); defer { lock.unlock() }; return clis.last }
    }

    private struct NoCloud: CloudWatchClient, PriceCatalog {
        func sums(namespace: String, dimension: String, metrics: [String], region: String, profile: String?,
                  from: Date, to: Date) async throws -> [String: [String: Double]] { [:] }
        func prices(service: String, ids: [String]) async -> [String: [String: String]] { [:] }
    }

    private func engine(settings: InMemoryProviderSettings = InMemoryProviderSettings(), clouds: Count = Count(),
                        passes: Count = Count()) -> Engine {
        Engine(settings: settings, vault: MemoryVault(),
               cloud: { clouds.add(); return (NoCloud(), NoCloud()) },
               guestPasses: { cli in
                   passes.ran(cli())
                   let source = MockGuestPassSource()
                   given(source).isAvailable().willReturn(true)
                   return source
               })
    }

    @Test
    func `should make a provider of every detected definition, in lineup order`() throws {
        let definitions = ProviderCatalog(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                                          extensions: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
            .detect()

        let providers = ProviderFactory.make(definitions, engine: engine())

        #expect(providers.map(\.id) == definitions.map(\.id))
        #expect(providers.first?.id == "claude")
    }

    @Test
    func `should give guest passes to the definition that declares them, at its CLI location`() throws {
        let settings = InMemoryProviderSettings()
        settings.setCLIPath("/opt/claude", forProvider: "claude")
        let passes = Count()
        let make = engine(settings: settings, passes: passes)

        let claude = ProviderFactory.make(try ProviderFactory.builtIn("claude"), engine: make)
        let codex = ProviderFactory.make(try ProviderFactory.builtIn("codex"), engine: make)

        #expect(claude.defaultAccount.guestPasses != nil)
        #expect(codex.defaultAccount.guestPasses == nil)
        #expect(passes.cli == "/opt/claude")
    }

    @Test
    func `should run guest passes with the definition's own CLI when the person chose no location`() throws {
        let passes = Count()
        _ = ProviderFactory.make(try ProviderFactory.builtIn("claude"), engine: engine(passes: passes))
        #expect(passes.cli == "claude")
    }

    @Test
    func `should make the cloud ports once, and only for a definition that reads the cloud`() throws {
        let clouds = Count()
        let shared = engine(clouds: clouds)

        _ = ProviderFactory.make(try ProviderFactory.builtIn("warp"), engine: shared)
        #expect(clouds.times == 0)

        _ = ProviderFactory.make(try ProviderFactory.builtIn("bedrock"), engine: shared)
        _ = ProviderFactory.make(try ProviderFactory.builtIn("bedrock"), engine: shared)
        #expect(clouds.times == 1)
    }

    @Test
    func `should find a custom provider's definition by its lineup id once it is made`() throws {
        let json = #"""
        {"profile":{"id":"custom-engine-test","name":"Engine Test"},"defaultDataSource":"api",
         "dataSources":[{"kind":"api","fetch":{"file":{"path":"~/x.json"}},"mapping":{"json":{"quotas":[]}}}]}
        """#
        let definition = try ProviderDefinition.parse(Data(json.utf8), origin: .custom)
        defer { ProviderFactory.unregister(custom: definition.id) }

        _ = ProviderFactory.make(definition, engine: engine())

        #expect(ProviderFactory.definition(forLineupId: "custom-engine-test")?.profile.name == "Engine Test")
    }

    @Test
    func `should read the plans that can send guest passes as declared in the definition`() throws {
        #expect(try ProviderFactory.builtIn("claude").guestPassPlans == ["claudeMax", "ULTRA"])
        #expect(try ProviderFactory.builtIn("codex").guestPassPlans == nil)
    }
}
