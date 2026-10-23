import Foundation
import Mockable
import Quotas
import Testing
@testable import DataSources

@Suite
struct ProgramTests {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("program-\(UUID().uuidString)", isDirectory: true)

    /// A runner that finds every program and answers `result`, or throws `error`.
    private func runner(_ result: CLIResult = CLIResult(output: "ok"), throwing error: (any Error)? = nil) -> MockCLIExecutor {
        let runner = MockCLIExecutor()
        given(runner).locate(.any).willProduce { "/bin/\($0)" }
        let execute = given(runner).execute(binary: .any, args: .any, input: .any, timeout: .any,
                                            workingDirectory: .any, autoResponses: .any)
        if let error { execute.willThrow(error) } else { execute.willReturn(result) }
        return runner
    }

    @Test
    func `should answer with what a program printed`() async throws {
        let program = try #require(Processes.running { _ in runner(CLIResult(output: "{\"used\":1}")) }.program(named: "acme"))
        #expect(try await program.run(["usage"], timeout: 5, in: nil) == "{\"used\":1}")
    }

    @Test
    func `should report the code a program exited with`() async throws {
        let program = try #require(Processes.running { _ in runner(CLIResult(output: "", exitCode: 2)) }.program(named: "acme"))
        await #expect { try await program.run(timeout: 5, in: nil) } throws: {
            ($0 as? CLIExitError).map { $0.cli == "acme" && $0.exitCode == 2 } ?? false
        }
    }

    @Test
    func `should report a program gone since it was found as missing`() async throws {
        let program = try #require(Processes.running { _ in runner(throwing: UsageError.cliNotFound("acme")) }.program(named: "acme"))
        await #expect { try await program.run(timeout: 5, in: nil) } throws: { ($0 as? CLIMissingError)?.cli == "acme" }
    }

    @Test
    func `should report a program that couldn't start`() async throws {
        let program = try #require(Processes.running { _ in runner(throwing: CocoaError(.fileReadNoPermission)) }.program(named: "acme"))
        await #expect { try await program.run(timeout: 5, in: nil) } throws: { ($0 as? CLILaunchError)?.cli == "acme" }
    }

    @Test
    func `should find no program that isn't installed`() {
        let runner = MockCLIExecutor()
        given(runner).locate(.any).willReturn(nil)
        #expect(Processes.running { _ in runner }.program(named: "acme") == nil)
    }

    @Test
    func `should run the person's script the way this OS starts one, naming it by its file`() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = folder.appendingPathComponent("probe.cmd").path
        try Data().write(to: URL(fileURLWithPath: path))
        let runner = runner(CLIResult(output: "", exitCode: 1))

        let script = try #require(Processes.running { _ in runner }.script(at: path))

        #expect(script.name == "probe.cmd")
        #expect(script.command == [path])
        await #expect { try await script.run(timeout: 5, in: folder) } throws: { ($0 as? CLIExitError)?.cli == "probe.cmd" }
    }

    @Test
    func `should find no script where no file is`() {
        #expect(Processes.running { _ in MockCLIExecutor() }.script(at: folder.appendingPathComponent("none").path) == nil)
    }

    @Test
    func `should talk to a program in the environment its OS gives it, with the call's changes`() throws {
        let seen = Seen()
        let processes = Processes.running { _ in runner() }
            .with(pipes: { _ in runner() }, conversation: { path, arguments, environment, _ in
                seen.record(path, arguments, environment)
                return MockRPCTransport()
            })
        let program = try #require(processes.program(named: "acme"))

        _ = try program.talk(["app-server"], environment: ProcessEnvironment(set: ["ACME_HOME": "/h"]), in: nil)

        #expect(seen.path == "/bin/acme")
        #expect(seen.arguments == ["app-server"])
        #expect(seen.environment?["ACME_HOME"] == "/h")
    }
}

private final class Seen: @unchecked Sendable {
    private(set) var path: String?
    private(set) var arguments: [String]?
    private(set) var environment: [String: String]?
    func record(_ path: String, _ arguments: [String], _ environment: [String: String]?) {
        self.path = path
        self.arguments = arguments
        self.environment = environment
    }
}
