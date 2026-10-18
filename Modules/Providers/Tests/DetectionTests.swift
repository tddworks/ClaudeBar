import DataSources
import Foundation
import Providers
import Testing

/// A definition on disk is a provider (TARGET_ARCHITECTURE §10): the bundle,
/// `~/.claudebar/providers` and `~/.claudebar/extensions` are read the same
/// way, ordered by each definition's own `order`, and no Swift lists one.
@Suite
struct DetectionTests {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private var custom: URL { root.appendingPathComponent("providers") }
    private var extensions: URL { root.appendingPathComponent("extensions") }

    private func detect() -> [ProviderDefinition] {
        ProviderCatalog(directory: custom, extensions: extensions).detect()
    }

    /// A custom definition file, as *Add Provider* saves it.
    private func write(custom id: String, name: String, order: Int? = nil) throws {
        try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
        let order = order.map { #","order":\#($0)"# } ?? ""
        let json = #"""
        {"profile":{"id":"\#(id)","name":"\#(name)"}\#(order),"defaultDataSource":"api",
         "dataSources":[{"kind":"api","fetch":{"file":{"path":"~/x.json"}},"mapping":{"json":{"quotas":[]}}}]}
        """#
        try Data(json.utf8).write(to: custom.appendingPathComponent("\(id).json"))
    }

    @Test
    func `should find every built-in in today's order without a list in Swift`() {
        let ids = detect().map(\.id)
        #expect(ids == ["claude", "codex", "gemini", "antigravity", "zai", "copilot", "bedrock", "ampcode", "kimi", "kiro",
                        "cursor", "minimax", "deepseek", "openrouter", "vercel-gateway", "alibaba", "mistral", "opencode-go",
                        "omp", "grok", "commandcode", "cline", "warp", "devin", "windsurf", "jetbrains", "openai",
                        "cloudflare-ai"])
        #expect(detect().allSatisfy { $0.profile.origin == .builtIn })
    }

    @Test
    func `should find a provider someone made, after the built-ins when it names no order`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try write(custom: "custom-zeta", name: "Zeta")
        try write(custom: "custom-alpha", name: "Alpha")

        let detected = detect()

        #expect(detected.suffix(2).map(\.id) == ["custom-alpha", "custom-zeta"])
        #expect(detected.last?.profile.origin == .custom)
    }

    @Test
    func `should place a provider by its own order`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try write(custom: "custom-early", name: "Early", order: 15)

        #expect(Array(detect().map(\.id).prefix(3)) == ["claude", "custom-early", "codex"])
    }

    @Test
    func `should keep a built-in's id for the built-in`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try write(custom: "warp", name: "Not Warp")

        let warps = detect().filter { $0.id == "warp" }

        #expect(warps.count == 1)
        #expect(warps.first?.profile.name == "Warp")
    }

    @Test
    func `should skip a file that isn't a definition and find the rest`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: custom.appendingPathComponent("broken.json"))
        try write(custom: "custom-fine", name: "Fine")

        #expect(detect().contains { $0.id == "custom-fine" })
    }

    @Test
    func `should find an extension as a provider`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        try FileManager.default.createDirectory(at: extensions, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: repo.appendingPathComponent("docs/features/providers/extensions/example-provider"),
                                         to: extensions.appendingPathComponent("example-provider"))

        let example = try #require(detect().first { $0.profile.origin == .extension })
        #expect(example.profile.name == "Example Provider")
    }
}
