#if canImport(Darwin) || canImport(Glibc)
import Quotas
import Foundation
import Testing

@testable import DataSources

/// Seconds since Foundation's reference date; only durations are ever taken
/// from it.
private func nowSeconds() -> Double { Date.timeIntervalSinceReferenceDate }

/// End-to-end cover for the PTY executor now that `execute` is async and hops
/// off the cooperative pool. Runs real binaries through a real pseudo-terminal —
/// the continuation/thread-hop plumbing is precisely what mocks would skip.
@Suite("DefaultCLIExecutor", .needsTerminal)
struct DefaultCLIExecutorTests {

    @Test
    func `should show what a CLI printed and its success in a terminal`() async throws {
        let result = try await DefaultCLIExecutor(installed: PlatformTerminal.installed, terminal: PlatformTerminal.terminal).execute(
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

    @Test
    func `should wait past a quiet spell while Claude's usage screen is still filling in (#271)`() async throws {
        // issue #271: `claude /usage` paints a placeholder, goes quiet longer
        // than the idle cutoff, then appends the quota bars.
        let result = try await DefaultCLIExecutor(installed: PlatformTerminal.installed, terminal: PlatformTerminal.terminal, completionRule: .claudeUsage).execute(
            binary: "/bin/sh",
            args: ["-c", "printf 'Loading usage data...'; sleep 5; printf 'Current session 1%% used'"],
            input: "",
            timeout: 20,
            workingDirectory: nil,
            autoResponses: [:]
        )

        #expect(result.output.contains("Current session"))
    }

    @Test
    func `should still deliver typed input after the stated delay`() async throws {
        // /bin/cat echoes back whatever it reads; the delay must not lose the
        // input, and the session must stay open long enough to receive it.
        let result = try await DefaultCLIExecutor(installed: PlatformTerminal.installed, terminal: PlatformTerminal.terminal, inputDelay: 1.0).execute(
            binary: "/bin/cat",
            args: [],
            input: "delayed-hello",
            timeout: 10,
            workingDirectory: nil,
            autoResponses: [:]
        )

        #expect(result.output.contains("delayed-hello"))
    }

    @Test
    func `should fail when the CLI can't be found`() async {
        await #expect(throws: (any Error).self) {
            try await DefaultCLIExecutor(installed: PlatformTerminal.installed, terminal: PlatformTerminal.terminal).execute(
                binary: "claudebar-missing-cli-xyz",
                args: [],
                input: "",
                timeout: 5,
                workingDirectory: nil,
                autoResponses: [:]
            )
        }
    }

    @Test
    func `should run the CLI in the folder it is given`() async throws {
        let result = try await DefaultCLIExecutor(installed: PlatformTerminal.installed, terminal: PlatformTerminal.terminal).execute(
            binary: "/bin/pwd",
            args: [],
            input: "",
            timeout: 20,
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            autoResponses: [:]
        )

        #expect(result.output.contains("tmp"))
    }

    @Test
    func `should start the CLI with the extra environment values it is given`() async throws {
        let result = try await DefaultCLIExecutor(
            installed: PlatformTerminal.installed,
            terminal: PlatformTerminal.terminal,
            environmentAdditions: ["CLAUDEBAR_PROBE": "1"]
        ).execute(
            binary: "/bin/sh",
            args: ["-c", "test \"$CLAUDEBAR_PROBE\" = 1 && echo marked"],
            input: "",
            timeout: 20,
            workingDirectory: nil,
            autoResponses: [:]
        )

        #expect(result.output.contains("marked"))
    }

    @Test
    func `should let several CLIs run at once without waiting on each other`() async throws {
        // The whole point of moving the blocking PTY run off the cooperative
        // pool: several providers refresh at once without serialising. The
        // four runs must share a moment — the last to begin starts before the
        // first to end — which holds on any machine at any speed, and fails
        // the moment the runs wait on each other.
        let count = 4

        let runs = try await withThrowingTaskGroup(of: (CLIResult, Double, Double).self) { group in
            for _ in 0..<count {
                group.addTask {
                    let began = nowSeconds()
                    let result = try await DefaultCLIExecutor(installed: PlatformTerminal.installed, terminal: PlatformTerminal.terminal).execute(
                        binary: "/bin/sh",
                        args: ["-c", "sleep 1; echo done"],
                        input: "",
                        timeout: 20,
                        workingDirectory: nil,
                        autoResponses: [:]
                    )
                    return (result, began, nowSeconds())
                }
            }
            var collected: [(CLIResult, Double, Double)] = []
            for try await run in group {
                #expect(run.0.output.contains("done"))
                collected.append(run)
            }
            return collected
        }

        let lastToBegin = try #require(runs.map(\.1).max())
        let firstToEnd = try #require(runs.map(\.2).min())
        #expect(lastToBegin < firstToEnd)
    }
}
#endif
