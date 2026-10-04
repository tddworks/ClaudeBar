import Foundation
import Mockable
import Quotas
import Testing
@testable import DataSources

/// A login file owned by a CLI is renewed by running that CLI once the token
/// is refused: the CLI writes its own file, which is read again — ClaudeBar
/// never writes it.
@Suite
struct CLIRefreshTests {
    private let definitionJSON = #"""
    {"kind":"api",
     "credential":{"jsonFile":{"path":"~/.acme/creds.json","token":"$.access_token"},
                   "refresh":{"cli":{"cli":"acme","input":"/quit\n","timeout":15}}},
     "fetch":{"http":{"url":"https://acme.test/usage","headers":{"Authorization":"Bearer {{token}}"}}},
     "mapping":{"json":{"quotas":[{"kind":"weekly","usedPercent":"used"}]}}}
    """#

    final class Seen: @unchecked Sendable {
        var tokens: [String] = []
        var runs: [String?] = []
    }

    private func make(home: URL, located: Bool = true, renewTo token: String? = "fresh", seen: Seen) throws -> DataSource {
        let definition = try JSONDecoder().decode(DataSourceDefinition.self, from: Data(definitionJSON.utf8))
        let file = home.appendingPathComponent(".acme/creds.json")
        let cli = MockCLIExecutor()
        given(cli).locate(.any).willReturn(located ? "/usr/local/bin/acme" : nil)
        given(cli).execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willProduce { _, _, input, _, _, _ in
                seen.runs.append(input)
                if let token { try? Data(#"{"access_token":"\#(token)","note":"cli"}"#.utf8).write(to: file) }
                return CLIResult(output: "")
            }
        let network = MockNetworkClient()
        given(network).request(.any).willProduce { request in
            let token = request.value(forHTTPHeaderField: "Authorization")?.replacingOccurrences(of: "Bearer ", with: "") ?? ""
            seen.tokens.append(token)
            let status = token == "fresh" ? 200 : 401
            return (Data(#"{"used":20}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        return DataSources.make(definition, providerId: "acme", makeCLIExecutor: { _ in cli }, makeCommandExecutor: { _ in cli },
                                network: network, makeTransport: { _, _, _, _ in MockRPCTransport() }, security: { _ in (1, "") },
                                scripts: { _ in nil }, secrets: nil, browserCookies: SystemBrowserCookies(),
                                environment: { _ in nil }, homeDirectory: home, now: { Date() })
    }

    private func home(token: String = "stale") throws -> (URL, () -> Void) {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".acme"), withIntermediateDirectories: true)
        try Data(#"{"access_token":"\#(token)"}"#.utf8).write(to: home.appendingPathComponent(".acme/creds.json"))
        return (home, { try? FileManager.default.removeItem(at: home) })
    }

    @Test func `a refused token runs the CLI and the renewed file is used`() async throws {
        let (home, cleanUp) = try home()
        defer { cleanUp() }
        let seen = Seen()

        let usage = try await make(home: home, seen: seen).fetchUsage()

        #expect(usage.quota(for: .weekly)?.percentRemaining == 80)
        #expect(seen.tokens == ["stale", "fresh"])
        #expect(seen.runs == ["/quit\n"])
        // The CLI's own file, untouched by us.
        let written = try String(contentsOf: home.appendingPathComponent(".acme/creds.json"), encoding: .utf8)
        #expect(written == #"{"access_token":"fresh","note":"cli"}"#)
    }

    @Test func `a working token never runs the CLI`() async throws {
        let (home, cleanUp) = try home(token: "fresh")
        defer { cleanUp() }
        let seen = Seen()

        _ = try await make(home: home, seen: seen).fetchUsage()

        #expect(seen.runs.isEmpty)
    }

    @Test func `with the CLI not installed the login is needed again`() async throws {
        let (home, cleanUp) = try home()
        defer { cleanUp() }

        await #expect { try await make(home: home, located: false, seen: Seen()).fetchUsage() } throws: {
            ($0 as? DataSourceError)?.reason == .authenticationRequired
        }
    }

    @Test func `a CLI that renews nothing leaves the token refused`() async throws {
        let (home, cleanUp) = try home()
        defer { cleanUp() }
        let seen = Seen()

        await #expect { try await make(home: home, renewTo: nil, seen: seen).fetchUsage() } throws: {
            ($0 as? DataSourceError)?.reason == .authenticationRequired
        }
        #expect(seen.tokens == ["stale", "stale"])
    }

    @Test func `the CLI refresh round-trips as written`() throws {
        let definition = try JSONDecoder().decode(DataSourceDefinition.self, from: Data(definitionJSON.utf8))
        #expect(try JSONDecoder().decode(DataSourceDefinition.self, from: JSONEncoder().encode(definition)) == definition)
        guard case .refreshing(_, .cli(let call))? = definition.credential else {
            Issue.record("Expected a CLI refresh"); return
        }
        #expect(call.cli == "acme")
    }
}
