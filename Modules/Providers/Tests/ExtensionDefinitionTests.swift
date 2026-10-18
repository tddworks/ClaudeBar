import DataSources
import Foundation
import Providers
import Quotas
import Testing

/// An extension's `manifest.json`, read as a definition of origin
/// *Extension* (docs/features/extensions/design.md). The person's file stays as it is.
@MainActor
@Suite
struct ExtensionDefinitionTests {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent("extensions-\(UUID().uuidString)", isDirectory: true)

    /// `docs/features/extensions/example-provider`, copied, its health check
    /// (a network call) taken out.
    private func example() throws -> URL {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let folder = root.appendingPathComponent("example-provider", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: repo.appendingPathComponent("docs/features/extensions/example-provider"), to: folder)
        let manifest = folder.appendingPathComponent("manifest.json")
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as! [String: Any]
        json["sections"] = (json["sections"] as! [[String: Any]]).filter { $0["type"] as? String != "healthCheck" }
        try JSONSerialization.data(withJSONObject: json).write(to: manifest)
        return folder
    }

    private func read(_ folder: URL) throws -> ProviderDefinition {
        try Extensions.definition(manifest: Data(contentsOf: folder.appendingPathComponent("manifest.json")), folder: folder)
    }

    @Test
    func `should show an extension under its manifest's name, symbol, colour and dashboard, marked as an extension`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let definition = try read(try example())

        #expect(definition.id == "ext-example-provider")
        #expect(definition.profile.name == "Example Provider")
        #expect(definition.profile.origin == .extension)
        #expect(definition.profile.look.symbol == "cpu.fill")
        #expect(definition.profile.look.color?.light == ProviderLook.RGB(1, 107.0 / 255, 53.0 / 255))
        #expect(definition.profile.links.dashboardTemplate == "https://example.com/usage")
        #expect(definition.together)
    }

    @Test
    func `should offer an extension's config fields as its settings, a toggle as on or off`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = Dictionary(uniqueKeysWithValues: try read(try example()).settings.map { ($0.id, $0) })

        #expect(settings["apiKey"]?.kind == .secret)
        #expect(settings["baseUrl"]?.default == "https://api.example.com")
        #expect(settings["monthlyBudget"]?.default == "100")
        if case .choice(let options)? = settings["verboseLogging"]?.kind {
            #expect(options.map(\.id) == ["true", "false"])
        } else {
            Issue.record("a toggle is a choice of on and off")
        }
    }

    @Test
    func `should run the extension's own script, with its key and settings, for each section it can read`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try example()
        let definition = try read(folder)

        #expect(definition.dataSources.map(\.kind) == ["quotas"])
        guard case .script(let call) = definition.dataSources[0].fetch else {
            Issue.record("a section runs its script"); return
        }
        #expect(call.run == "./probe-quota.sh")
        #expect(call.folder == folder.path)
        #expect(call.secrets == ["CLAUDEBAR_API_KEY": "apiKey"])
        #expect(call.environment["CLAUDEBAR_BASE_URL"] == "{{setting.baseUrl}}")
        #expect(definition.dataSources[0].mapping == .usage(UsageMapping()))
    }

    @Test(.needsPOSIXShell)
    func `should show the example extension's session and weekly quotas`() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let provider = ProviderFactory.make(try read(try example()), settings: InMemoryProviderSettings())

        let usage = try await provider.refreshPlain()

        #expect(usage.quota(for: .session)?.percentRemaining == 85)
        #expect(usage.quota(for: .weekly)?.percentRemaining == 62)
    }

    @Test
    func `should check an extension's health by asking its URL within its timeout`() throws {
        let definition = try Extensions.definition(manifest: Data("""
        {"id":"up","name":"Up","version":"1","sections":[
          {"id":"health","type":"healthCheck","probe":{"builtIn":"healthCheck","url":"https://example.com/health","timeout":5}}]}
        """.utf8), folder: root)

        guard case .http(let request) = definition.dataSources[0].fetch else {
            Issue.record("a health check is a request"); return
        }
        #expect(request.url == "https://example.com/health")
        #expect(request.timeout == 5)
    }

    @Test
    func `should refuse an extension with no section it can read`() {
        #expect(throws: (any Error).self) {
            try Extensions.definition(manifest: Data("""
            {"id":"m","name":"M","version":"1","sections":[{"id":"m","type":"metricsRow","probe":{"command":"./m.sh"}}]}
            """.utf8), folder: root)
        }
    }

    @Test
    func `should list every extension and skip one whose manifest is damaged`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try example()
        let broken = root.appendingPathComponent("broken", isDirectory: true)
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: broken.appendingPathComponent("manifest.json"))

        #expect(Extensions.catalog(in: root).map(\.id) == ["ext-example-provider"])
    }

    @Test
    func `should not list a folder that has no manifest`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("notes", isDirectory: true), withIntermediateDirectories: true)

        #expect(Extensions.catalog(in: root).isEmpty)
    }

    @Test
    func `should list no extensions when there is no extensions folder`() {
        #expect(Extensions.catalog(in: root.appendingPathComponent("missing")).isEmpty)
    }

    @Test
    func `should hand each setting to the script under a CLAUDEBAR_ name built from its id`() throws {
        let definition = try Extensions.definition(manifest: Data("""
        {"id":"names","name":"Names","version":"1",
         "config":[{"id":"apiKey","label":"Key","type":"secret"},{"id":"port","label":"Port","type":"number"},
                   {"id":"base-url","label":"URL","type":"string"},{"id":"monthlyBudget","label":"Budget","type":"number"}],
         "sections":[{"id":"quotas","type":"quotaGrid","probe":{"command":"./probe.sh"}}]}
        """.utf8), folder: root)
        guard case .script(let call) = definition.dataSources[0].fetch else { Issue.record("a script"); return }

        #expect(Set(call.secrets.keys) == ["CLAUDEBAR_API_KEY"])
        #expect(Set(call.environment.keys) == ["CLAUDEBAR_PORT", "CLAUDEBAR_BASE_URL", "CLAUDEBAR_MONTHLY_BUDGET"])
    }
}
