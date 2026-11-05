import Quotas
import Foundation
import Mockable
import Testing
@testable import DataSources

/// `command` — a CLI run over pipes; its exit code is a fact, never ignored.
@Suite
struct CommandTests {
    private func decode(_ json: String) throws -> DataSourceDefinition {
        try JSONDecoder().decode(DataSourceDefinition.self, from: Data(json.utf8))
    }

    private func make(_ definition: DataSourceDefinition, executor: MockCLIExecutor, environment: [String: String] = [:]) -> DataSource {
        DataSources.make(definition, providerId: "acme", cliExecutor: executor, network: MockNetworkClient(),
                         makeTransport: { _, _, _, _ in MockRPCTransport() }, environment: { environment[$0] },
                         homeDirectory: FileManager.default.temporaryDirectory, now: { Date() })
    }

    private func executor(output: String, exitCode: Int32 = 0, found: Bool = true) -> MockCLIExecutor {
        let executor = MockCLIExecutor()
        given(executor).locate(.any).willReturn(found ? "/usr/local/bin/acme" : nil)
        given(executor).execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willReturn(CLIResult(output: output, exitCode: exitCode))
        return executor
    }

    private let usage = """
    {"kind":"cli","credential":{"environment":"ACME_KEY"},
     "fetch":{"command":{"cli":"acme","args":["usage","--json"],"environment":{"set":{"ACME_TOKEN":"{{token}}"}}}},
     "mapping":{"json":{"quotas":[{"kind":"weekly","usedPercent":"used"}]}}}
    """

    @Test
    func `should show the quota a command prints`() async throws {
        let source = make(try decode(usage), executor: executor(output: #"{"used":30}"#), environment: ["ACME_KEY": "k"])

        let result = try await source.fetchUsage()

        #expect(result.quota(for: .weekly)?.percentRemaining == 70)
    }

    @Test
    func `should fail at fetching, naming the exit code, when the command exits with an error`() async throws {
        let source = make(try decode(usage), executor: executor(output: #"{"used":30}"#, exitCode: 2), environment: ["ACME_KEY": "k"])

        await #expect { try await source.fetchUsage() } throws: { error in
            guard let error = error as? DataSourceError, error.step == .fetch,
                  case .executionFailed(let message) = error.reason else { return false }
            return message == "`acme` exited with code 2"
        }
    }

    @Test
    func `should say the CLI is not found, and not be ready, when it isn't installed`() async throws {
        let source = make(try decode(usage), executor: executor(output: "", found: false), environment: ["ACME_KEY": "k"])

        await #expect { try await source.fetchUsage() } throws: { ($0 as? DataSourceError)?.reason == .cliNotFound("acme") }
        #expect(await source.isReady() == false)
    }

    @Test
    func `should say the CLI is missing in the definition's words when it disappears just before running`() async throws {
        let executor = MockCLIExecutor()
        given(executor).locate(.any).willReturn("/usr/local/bin/acme")
        given(executor).execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willThrow(UsageError.cliNotFound("acme"))
        let definition = try decode("""
        {"kind":"cli","fetch":{"command":{"cli":"acme"}},"mapping":{"json":{"quotas":[]}},
         "errors":{"cli.missing":{"cliNotFound":"Acme CLI"}}}
        """)

        await #expect { try await make(definition, executor: executor).fetchUsage() } throws: {
            ($0 as? DataSourceError)?.reason == .cliNotFound("Acme CLI")
        }
    }

    @Test
    func `should show the quota when the command is given its input text`() async throws {
        let executor = MockCLIExecutor()
        given(executor).locate(.any).willReturn("/usr/local/bin/acme")
        given(executor).execute(binary: .any, args: .any, input: .value("/usage\n/quit\n"), timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willReturn(CLIResult(output: #"{"used":30}"#, exitCode: 0))
        let source = make(try decode("""
        {"kind":"cli","fetch":{"command":{"cli":"acme","input":"/usage\\n/quit\\n"}},
         "mapping":{"json":{"quotas":[{"kind":"weekly","usedPercent":"used"}]}}}
        """), executor: executor)

        #expect(try await source.fetchUsage().quota(for: .weekly)?.percentRemaining == 70)
    }

    @Test
    func `should show the quota a command prints after its timeout when the host allows it time to start (#685)`() async throws {
        // A CLI read from a cold disk in WSL: it needs 15 s, its definition gives it 10.
        let executor = MockCLIExecutor()
        given(executor).locate(.any).willReturn("/usr/local/bin/acme")
        given(executor).execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willProduce { _, _, _, timeout, _, _ in
                guard timeout >= 15 else { throw UsageError.timeout }
                return CLIResult(output: #"{"used":30}"#, exitCode: 0)
            }
        let source = make(try decode("""
        {"kind":"cli","fetch":{"command":{"cli":"acme","timeout":10}},
         "mapping":{"json":{"quotas":[{"kind":"weekly","usedPercent":"used"}]}}}
        """), executor: executor)

        let usage = try await FetchContext.$startAllowance.withValue(10) { try await source.fetchUsage() }

        #expect(usage.quota(for: .weekly)?.percentRemaining == 70)
    }

    @Test
    func `should hand the key to the command only through its environment`() throws {
        let environment = try ProcessEnvironment(set: ["ACME_TOKEN": "{{token}}"]).filled(with: Credential(["token": "k-1"]))
        #expect(environment.set == ["ACME_TOKEN": "k-1"])
    }

    @Test
    func `should ask to sign in when the command's environment needs a key there isn't`() {
        #expect(throws: UsageError.authenticationRequired) {
            try ProcessEnvironment(set: ["ACME_TOKEN": "{{token}}"]).filled(with: nil)
        }
    }

    @Test
    func `should tell a piped command from a terminal CLI in the definition`() throws {
        let command = try decode(usage).fetch
        let terminal = try decode(#"{"kind":"cli","fetch":{"cli":{"cli":"acme","input":"/usage"}},"mapping":{"json":{"quotas":[]}}}"#).fetch
        guard case .command(let call) = command else { Issue.record("not a command"); return }
        guard case .cli(let session) = terminal else { Issue.record("not a terminal cli"); return }
        #expect(call.args == ["usage", "--json"])
        #expect(session.input == "/usage")
    }
}
