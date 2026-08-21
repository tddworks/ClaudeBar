import Foundation
import Testing

@testable import Infrastructure

/// Exercises the Subprocess-backed runner against real fixture binaries rather
/// than mocks — the failure modes being guarded here (pipe-buffer deadlock,
/// unreaped children, lost exit codes) only appear against a real process.
@Suite("SubprocessSupport")
struct SubprocessSupportTests {

    @Test("Captures standard output and a successful exit code")
    func capturesStandardOutput() async throws {
        let result = try await SubprocessSupport.run(
            executablePath: "/bin/echo",
            arguments: ["hello"]
        )

        #expect(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "hello")
        #expect(result.exitCode == 0)
        #expect(result.isSuccess)
    }

    @Test("Returns a non-zero exit code instead of throwing")
    func nonZeroExitIsNotAnError() async throws {
        let result = try await SubprocessSupport.run(
            executablePath: "/usr/bin/false",
            arguments: []
        )

        #expect(result.exitCode != 0)
        #expect(!result.isSuccess)
    }

    @Test("Captures standard error separately from standard output")
    func capturesStandardError() async throws {
        let result = try await SubprocessSupport.run(
            executablePath: "/bin/sh",
            arguments: ["-c", "echo out; echo err 1>&2; exit 3"]
        )

        #expect(result.standardOutput.contains("out"))
        #expect(result.standardError.contains("err"))
        #expect(result.standardOutput.contains("err") == false)
        #expect(result.exitCode == 3)
    }

    @Test("Writes input to the child's standard input")
    func forwardsInput() async throws {
        let result = try await SubprocessSupport.run(
            executablePath: "/bin/cat",
            arguments: [],
            input: "piped-value"
        )

        #expect(result.standardOutput == "piped-value")
    }

    @Test("Closes standard input when no input is supplied")
    func closesStdinWithoutInput() async throws {
        // `cat` with a closed stdin exits cleanly instead of hanging forever.
        let result = try await SubprocessSupport.run(
            executablePath: "/bin/cat",
            arguments: []
        )

        #expect(result.standardOutput.isEmpty)
        #expect(result.exitCode == 0)
    }

    @Test("Collects output far larger than the OS pipe buffer")
    func handlesOutputLargerThanPipeBuffer() async throws {
        // ~290 KB, several times the ~64 KB pipe buffer. The previous
        // `waitUntilExit()`-then-read ordering deadlocks on exactly this.
        let result = try await SubprocessSupport.run(
            executablePath: "/bin/sh",
            arguments: ["-c", "seq 1 50000"]
        )

        #expect(result.exitCode == 0)
        #expect(result.standardOutput.count > 200_000)
        #expect(result.standardOutput.hasPrefix("1\n"))
        #expect(result.standardOutput.hasSuffix("50000\n"))
    }

    @Test("Reports a signalled child as a non-zero exit code")
    func reportsSignalledChild() async throws {
        let result = try await SubprocessSupport.run(
            executablePath: "/bin/sh",
            arguments: ["-c", "kill -TERM $$"]
        )

        #expect(!result.isSuccess)
    }

    @Test("Throws when the executable does not exist")
    func throwsForMissingExecutable() async {
        await #expect(throws: (any Error).self) {
            try await SubprocessSupport.run(
                executablePath: "/nonexistent/claudebar-not-a-binary",
                arguments: []
            )
        }
    }

    @Test("Runs in the requested working directory")
    func honoursWorkingDirectory() async throws {
        let result = try await SubprocessSupport.run(
            executablePath: "/bin/pwd",
            arguments: [],
            workingDirectory: "/tmp"
        )

        #expect(result.standardOutput.contains("tmp"))
    }

    @Test("Cancelling the calling task tears the child down")
    func cancellationTearsDownChild() async throws {
        let task = Task {
            try await SubprocessSupport.run(
                executablePath: "/bin/sh",
                arguments: ["-c", "sleep 30"]
            )
        }

        // Give the child time to actually spawn before cancelling.
        try await Task.sleep(for: .milliseconds(200))

        let start = CFAbsoluteTimeGetCurrent()
        task.cancel()
        _ = try? await task.value
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        // Must return promptly rather than waiting out the full 30s sleep.
        #expect(elapsed < 10)
    }
}
