import Foundation
import Mockable
import Testing
@testable import DataSources

/// *Configured* — what `isReady` answers before anything runs.
@Suite
struct ReadinessTests {
    private func make(requiresFiles: [String]) -> DataSource {
        let definition = DataSourceDefinition(kind: "file", fetch: .http(HTTPRequest(url: "https://acme.test")),
                                              mapping: .script(ScriptMapping(file: "none.js")), requiresFiles: requiresFiles)
        return DataSources.make(definition, providerId: "acme", cliExecutor: MockCLIExecutor(), network: MockNetworkClient(),
                                makeTransport: { _, _, _, _ in MockRPCTransport() }, environment: { _ in nil },
                                homeDirectory: FileManager.default.temporaryDirectory, now: { Date() })
    }

    @Test
    func `a data source whose required file is missing is not configured`() async {
        #expect(await make(requiresFiles: ["/no/such/acme/login.json"]).isReady() == false)
    }

    @Test
    func `a data source whose required files exist is configured`() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("acme-\(UUID().uuidString).json")
        try Data("{}".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(await make(requiresFiles: [file.path]).isReady() == true)
    }
}
