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
    func `a command's output is read as its response`() async throws {
        let source = make(try decode(usage), executor: executor(output: #"{"used":30}"#), environment: ["ACME_KEY": "k"])

        let result = try await source.fetchUsage()

        #expect(result.quota(for: .weekly)?.percentRemaining == 70)
    }

    @Test
    func `a non-zero exit is a failure at the fetch step, not output to map`() async throws {
        let source = make(try decode(usage), executor: executor(output: #"{"used":30}"#, exitCode: 2), environment: ["ACME_KEY": "k"])

        await #expect { try await source.fetchUsage() } throws: { error in
            guard let error = error as? DataSourceError, error.step == .fetch,
                  case .executionFailed(let message) = error.reason else { return false }
            return message == "`acme` exited with code 2"
        }
    }

    @Test
    func `a missing CLI says so before anything runs`() async throws {
        let source = make(try decode(usage), executor: executor(output: "", found: false), environment: ["ACME_KEY": "k"])

        await #expect { try await source.fetchUsage() } throws: { ($0 as? DataSourceError)?.reason == .cliNotFound("acme") }
        #expect(await source.isReady() == false)
    }

    @Test
    func `a CLI gone between the check and the run is still a missing CLI the definition can word`() async throws {
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
    func `a command can be given text on its standard input`() async throws {
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
    func `the token reaches the command through its environment only`() throws {
        let environment = try ProcessEnvironment(set: ["ACME_TOKEN": "{{token}}"]).filled(with: Credential(["token": "k-1"]))
        #expect(environment.set == ["ACME_TOKEN": "k-1"])
    }

    @Test
    func `an environment value naming an unknown credential means the key is missing`() {
        #expect(throws: UsageError.authenticationRequired) {
            try ProcessEnvironment(set: ["ACME_TOKEN": "{{token}}"]).filled(with: nil)
        }
    }

    @Test
    func `a command and a terminal cli decode as different cases`() throws {
        let command = try decode(usage).fetch
        let terminal = try decode(#"{"kind":"cli","fetch":{"cli":{"cli":"acme","input":"/usage"}},"mapping":{"json":{"quotas":[]}}}"#).fetch
        guard case .command(let call) = command else { Issue.record("not a command"); return }
        guard case .cli(let session) = terminal else { Issue.record("not a terminal cli"); return }
        #expect(call.args == ["usage", "--json"])
        #expect(session.input == "/usage")
    }
}
