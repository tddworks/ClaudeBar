import Foundation
import Mockable
import Quotas
import Testing
@testable import DataSources

/// `sqlite` — a key another app keeps in its own database, read without
/// ever writing to it; and `{{token#jwt.claim}}` for what the key says.
@Suite
struct DatabaseCredentialTests {
    private static let token = "header.eyJzdWIiOiJ3b3JrLXVzZXIifQ.signature"

    private struct Vault: SecretStore {
        let token: String
        func secret(_ name: String, provider: String) -> String? { token }
    }

    private func source(_ credential: String, token: String = Self.token) throws -> (DataSource, Sent) {
        let json = """
        {"kind":"api","credential":\(credential),
         "fetch":{"http":{"url":"https://acme.test","headers":{"Cookie":"{{token#jwt.sub}}::{{token}}"}}},
         "mapping":{"json":{"quotas":[]}}}
        """
        let definition = try JSONDecoder().decode(DataSourceDefinition.self, from: Data(json.utf8))
        let network = MockNetworkClient()
        let sent = Sent()
        given(network).request(.any).willProduce { @Sendable request in
            sent.record(request)
            return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let source = DataSources.make(definition, providerId: "acme", cliExecutor: MockCLIExecutor(), network: network,
                                      makeTransport: { _, _, _, _ in MockRPCTransport() }, secrets: Vault(token: token),
                                      environment: { _ in nil }, homeDirectory: FileManager.default.temporaryDirectory, now: { Date() })
        return (source, sent)
    }

    private func database(_ sql: String) throws -> (URL, () -> Void) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("state.db")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [file.path, sql]
        try process.run()
        process.waitUntilExit()
        return (file, { try? FileManager.default.removeItem(at: root) })
    }

    @Test
    func `a key is read from another app's database, which is never written`() async throws {
        let (file, cleanUp) = try database("CREATE TABLE items(key TEXT, value TEXT); INSERT INTO items VALUES ('auth', '\(Self.token)');")
        defer { cleanUp() }
        let before = try Data(contentsOf: file)
        let (source, sent) = try source(#"{"sqlite":{"path":"\#(file.path)","query":"SELECT value AS token FROM items WHERE key = 'auth'","fields":{"token":"$.token"}}}"#)

        _ = try await source.fetchResponse()

        #expect(sent.header("Cookie", at: "") == "work-user::\(Self.token)")
        #expect(try Data(contentsOf: file) == before)
    }

    @Test
    func `a query that changes the database is refused`() async throws {
        let (file, cleanUp) = try database("CREATE TABLE items(value TEXT);")
        defer { cleanUp() }
        let (source, _) = try source(#"{"sqlite":{"path":"\#(file.path)","query":"DELETE FROM items","fields":{"token":"$.token"}}}"#)

        await #expect { try await source.fetchResponse() } throws: { ($0 as? DataSourceError)?.step == .lookup }
    }

    @Test
    func `a database with no such row has no key`() async throws {
        let (file, cleanUp) = try database("CREATE TABLE items(key TEXT, value TEXT);")
        defer { cleanUp() }
        let (source, _) = try source(#"{"sqlite":{"path":"\#(file.path)","query":"SELECT value AS token FROM items","fields":{"token":"$.token"}}}"#)

        await #expect { try await source.fetchResponse() } throws: { ($0 as? DataSourceError)?.reason == .authenticationRequired }
    }

    @Test
    func `a claim of the key fills a template, whatever lookup found the key`() async throws {
        let (source, sent) = try source(#"{"setting":"token"}"#)

        _ = try await source.fetchResponse()

        #expect(sent.header("Cookie", at: "") == "work-user::\(Self.token)")
    }

    @Test
    func `a lookup's hint is what Settings says to do`() throws {
        let lookup = try JSONDecoder().decode(CredentialLookup.self, from: Data(#"{"sqlite":{"path":"~/x.db","query":"SELECT 1","fields":{},"hint":"Sign in again in Acme."}}"#.utf8))
        #expect(lookup.hint == "Sign in again in Acme.")
        #expect(lookup.lookupOrder == ["~/x.db"])
    }
}
