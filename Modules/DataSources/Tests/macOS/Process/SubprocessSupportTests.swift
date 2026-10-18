#if os(macOS)
import Foundation
import Testing

@testable import DataSources

/// Exercises the Subprocess-backed runner against real fixture binaries rather
/// than mocks — the failure modes being guarded here (pipe-buffer deadlock,
/// unreaped children, lost exit codes) only appear against a real process.
@Suite("SubprocessSupport")
struct SubprocessSupportTests {

    @Test(arguments: [
        QualityOfService.userInteractive, .userInitiated, .utility, .background, .default,
    ])
    func `should hear what a program prints at every quality of service`(qualityOfService: QualityOfService) async throws {
        let result = try await SubprocessSupport.run(
            executablePath: "/bin/echo",
            arguments: ["hello"],
            qualityOfService: qualityOfService
        )

        #expect(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "hello")
        #expect(result.exitCode == 0)
        #expect(result.isSuccess)
    }

    @Test
    func `should report a failing program's exit code without failing the run`() async throws {
        let result = try await SubprocessSupport.run(
            executablePath: "/usr/bin/false",
            arguments: []
        )

        #expect(result.exitCode != 0)
        #expect(!result.isSuccess)
    }

    @Test
    func `should hear a program's errors apart from what it prints`() async throws {
        let result = try await SubprocessSupport.run(
            executablePath: "/bin/sh",
            arguments: ["-c", "echo out; echo err 1>&2; exit 3"]
        )

        #expect(result.standardOutput.contains("out"))
        #expect(result.standardError.contains("err"))
        #expect(result.standardOutput.contains("err") == false)
        #expect(result.exitCode == 3)
    }

    @Test
    func `should hand a program the input it is given`() async throws {
        let result = try await SubprocessSupport.run(
            executablePath: "/bin/cat",
            arguments: [],
            input: "piped-value"
        )

        #expect(result.standardOutput == "piped-value")
    }

    @Test
    func `should not leave a program waiting for input when there is none`() async throws {
        // `cat` with a closed stdin exits cleanly instead of hanging forever.
        let result = try await SubprocessSupport.run(
            executablePath: "/bin/cat",
            arguments: []
        )

        #expect(result.standardOutput.isEmpty)
        #expect(result.exitCode == 0)
    }

    @Test
    func `should hear everything a program prints when it is far more than a pipe holds`() async throws {
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

    @Test
    func `should report a program killed by a signal as failed`() async throws {
        let result = try await SubprocessSupport.run(
            executablePath: "/bin/sh",
            arguments: ["-c", "kill -TERM $$"]
        )

        #expect(!result.isSuccess)
    }

    @Test
    func `should fail when the program does not exist`() async {
        await #expect(throws: (any Error).self) {
            try await SubprocessSupport.run(
                executablePath: "/nonexistent/claudebar-not-a-binary",
                arguments: []
            )
        }
    }

    @Test
    func `should run a program in the folder it is asked to`() async throws {
        let result = try await SubprocessSupport.run(
            executablePath: "/bin/pwd",
            arguments: [],
            workingDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)
        )

        #expect(result.standardOutput.contains("tmp"))
    }

    @Test
    func `should stop the program promptly when its run is cancelled`() async throws {
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
#endif
