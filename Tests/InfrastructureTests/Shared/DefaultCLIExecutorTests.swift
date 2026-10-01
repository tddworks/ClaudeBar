import Domain
import Foundation
import Testing

@testable import Infrastructure

/// End-to-end cover for the PTY executor now that `execute` is async and hops
/// off the cooperative pool. Runs real binaries through a real pseudo-terminal —
/// the continuation/thread-hop plumbing is precisely what mocks would skip.
@Suite("DefaultCLIExecutor")
struct DefaultCLIExecutorTests {

    @Test("Executes a command and returns its output")
    func executesCommand() async throws {
        let result = try await DefaultCLIExecutor().execute(
            binary: "/bin/echo",
            args: ["pty-hello"],
            input: "",
            timeout: 20,
            workingDirectory: nil,
            autoResponses: [:]
        )

        #expect(result.output.contains("pty-hello"))
        #expect(result.exitCode == 0)
    }

    @Test("Waits past an idle gap while the screen is still filling in")
    func waitsForPendingScreen() async throws {
        // issue #271: `claude /usage` paints a placeholder, goes quiet longer
        // than the idle cutoff, then appends the quota bars.
        let result = try await DefaultCLIExecutor(completionRule: .claudeUsage).execute(
            binary: "/bin/sh",
            args: ["-c", "printf 'Loading usage data...'; sleep 5; printf 'Current session 1%% used'"],
            input: "",
            timeout: 20,
            workingDirectory: nil,
            autoResponses: [:]
        )

        #expect(result.output.contains("Current session"))
    }

    @Test("Throws when the binary cannot be located")
    func throwsForMissingBinary() async {
        await #expect(throws: (any Error).self) {
            try await DefaultCLIExecutor().execute(
                binary: "claudebar-missing-cli-xyz",
                args: [],
                input: "",
                timeout: 5,
                workingDirectory: nil,
                autoResponses: [:]
            )
        }
    }

    @Test("Runs in the supplied working directory")
    func honoursWorkingDirectory() async throws {
        let result = try await DefaultCLIExecutor().execute(
            binary: "/bin/pwd",
            args: [],
            input: "",
            timeout: 20,
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            autoResponses: [:]
        )

        #expect(result.output.contains("tmp"))
    }

    @Test("Concurrent executions do not block one another")
    func concurrentExecutionsProceedInParallel() async throws {
        // The whole point of moving the blocking PTY run off the cooperative
        // pool: several providers refresh at once without serialising. Each
        // command sleeps, so a serialised implementation would take N x 1s.
        let count = 4
        let start = CFAbsoluteTimeGetCurrent()

        try await withThrowingTaskGroup(of: CLIResult.self) { group in
            for _ in 0..<count {
                group.addTask {
                    try await DefaultCLIExecutor().execute(
                        binary: "/bin/sh",
                        args: ["-c", "sleep 1; echo done"],
                        input: "",
                        timeout: 20,
                        workingDirectory: nil,
                        autoResponses: [:]
                    )
                }
            }
            for try await result in group {
                #expect(result.output.contains("done"))
            }
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - start
        // Generous bound: parallel is ~1s plus PTY setup, serial would be ~4s+.
        #expect(elapsed < 3.0)
    }
}
