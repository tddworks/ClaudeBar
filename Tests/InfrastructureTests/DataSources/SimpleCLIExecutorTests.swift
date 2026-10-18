import Domain
import Foundation
import Testing
@testable import Infrastructure

@Suite
struct SimpleCLIExecutorTests {

    // MARK: - PATH Augmentation
    //
    // Menu bar apps launched by launchd get a minimal PATH; script CLIs
    // with `/usr/bin/env` shebangs (bun/node) need their runtime findable.

    @Test
    func `should let a CLI find the runtime that sits beside it when launched from the menu bar`() {
        let env = SimpleCLIExecutor.augmentedEnvironment(binaryPath: "/test-omp-home/.bun/bin/omp")
        let entries = (env["PATH"] ?? "").split(separator: ":").map(String.init)

        // The runtime (bun) usually lives next to the tool it runs.
        #expect(entries.filter { $0 == "/test-omp-home/.bun/bin" }.count == 1)
    }

    @Test
    func `should keep the person's PATH first and add the usual tool folders after it`() {
        let env = SimpleCLIExecutor.augmentedEnvironment(binaryPath: "/usr/bin/true")
        let entries = (env["PATH"] ?? "").split(separator: ":").map(String.init)

        if let currentFirst = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").first.map(String.init) {
            #expect(entries.first == currentFirst)
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(entries.contains("\(home)/.bun/bin"))
        #expect(entries.contains("\(home)/.local/bin"))
    }

    // MARK: - Execution

    @Test
    func `should give back what the CLI printed and its exit code`() async throws {
        let result = try await SimpleCLIExecutor().execute(
            binary: "/bin/echo",
            args: ["kiro-output"],
            input: nil,
            timeout: 10,
            workingDirectory: nil,
            autoResponses: [:]
        )

        #expect(result.output.contains("kiro-output"))
        #expect(result.exitCode == 0)
    }

    @Test
    func `should report a CLI's failing exit code rather than fail`() async throws {
        let result = try await SimpleCLIExecutor().execute(
            binary: "/bin/sh",
            args: ["-c", "exit 7"],
            input: nil,
            timeout: 10,
            workingDirectory: nil,
            autoResponses: [:]
        )

        #expect(result.exitCode == 7)
    }

    @Test
    func `should give back what the CLI printed to both output and error`() async throws {
        let result = try await SimpleCLIExecutor().execute(
            binary: "/bin/sh",
            args: ["-c", "echo out; echo err 1>&2"],
            input: nil,
            timeout: 10,
            workingDirectory: nil,
            autoResponses: [:]
        )

        #expect(result.output.contains("out"))
        #expect(result.output.contains("err"))
    }

    @Test
    func `should say the CLI is not found when it is not installed`() async {
        await #expect(throws: UsageError.cliNotFound("claudebar-not-a-real-cli")) {
            try await SimpleCLIExecutor().execute(
                binary: "claudebar-not-a-real-cli",
                args: [],
                input: nil,
                timeout: 10,
                workingDirectory: nil,
                autoResponses: [:]
            )
        }
    }

    @Test
    func `should say the command timed out, near the timeout, when a CLI never finishes`() async {
        let start = CFAbsoluteTimeGetCurrent()

        await #expect(throws: UsageError.executionFailed("Command timed out after 0.5 seconds")) {
            try await SimpleCLIExecutor().execute(
                binary: "/bin/sh",
                args: ["-c", "sleep 30"],
                input: nil,
                timeout: 0.5,
                workingDirectory: nil,
                autoResponses: [:]
            )
        }

        // Must give up near the timeout, not ride out the full sleep.
        #expect(CFAbsoluteTimeGetCurrent() - start < 10)
    }

    @Test
    func `should give back all of a CLI's output when it prints a lot`() async throws {
        // The previous implementation raced two DispatchQueue readers against a
        // usleep poll loop; this is the case that made that fragile.
        let result = try await SimpleCLIExecutor().execute(
            binary: "/bin/sh",
            args: ["-c", "seq 1 50000"],
            input: nil,
            timeout: 20,
            workingDirectory: nil,
            autoResponses: [:]
        )

        #expect(result.exitCode == 0)
        #expect(result.output.count > 200_000)
    }

    @Test
    func `should not add a tool folder the PATH already has`() {
        let env = SimpleCLIExecutor.augmentedEnvironment(binaryPath: "/opt/homebrew/bin/tool")
        let entries = (env["PATH"] ?? "").split(separator: ":").map(String.init)

        // /opt/homebrew/bin is both the binary dir and a common path —
        // it must be appended at most once beyond any ambient occurrence.
        let ambient = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map(String.init)
        let ambientCount = ambient.filter { $0 == "/opt/homebrew/bin" }.count
        let augmentedCount = entries.filter { $0 == "/opt/homebrew/bin" }.count
        #expect(augmentedCount == max(ambientCount, 1))
    }
}
