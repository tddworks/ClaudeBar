#if canImport(Darwin) || canImport(Glibc)
import Testing
import Foundation
@testable import DataSources

/// Ending a child a fetch started has a bound (#550): a refresh's deadline
/// closes the CLI it started, and a child still there after `SIGKILL` used to
/// hold that close, the refresh, and every later one, on "Syncing..." forever.
@Suite(.timeLimit(.minutes(1)))
struct ChildTeardownTests {
    /// A child that is asked, then made, to stop, and never does.
    private final class StuckChild: @unchecked Sendable {
        private let lock = NSLock()
        private var asked: [String] = []
        var signals: [String] { lock.lock(); defer { lock.unlock() }; return asked }
        func record(_ signal: String) { lock.lock(); asked.append(signal); lock.unlock() }
    }

    @Test func `should give up on a child that outlives SIGKILL, after asking and then making it stop`() {
        let child = StuckChild()
        let started = Date()

        let ended = ChildTeardown.end(
            isRunning: { true },
            terminate: { child.record("TERM") },
            kill: { child.record("KILL") },
            grace: 0.2,
            afterKill: 0.2
        )

        #expect(!ended)
        #expect(child.signals == ["TERM", "KILL"])
        #expect(Date().timeIntervalSince(started) < 2)
    }

    @Test func `should make a real child stop when it ignores the request to`() throws {
        let process = Process()
        let ready = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // It says so once the request to stop is ignored, then never ends on its own.
        process.arguments = ["-c", "trap '' TERM; echo ready; while :; do sleep 1; done"]
        process.standardOutput = ready
        process.standardError = FileHandle.nullDevice
        try process.run()
        // If the teardown fails, the child must not outlive the test run.
        defer { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
        #expect(try ready.fileHandleForReading.read(upToCount: 1) == Data("r".utf8))

        #expect(ChildTeardown.end(process, named: "test child", grace: 0.2))
        try #require(!process.isRunning)
        // Only SIGKILL ended it: the request to stop alone did not.
        #expect(process.terminationReason == .uncaughtSignal)
        #expect(process.terminationStatus == SIGKILL)
    }

    @Test func `should not signal a child that has already exited`() {
        let child = StuckChild()

        let ended = ChildTeardown.end(
            isRunning: { false },
            terminate: { child.record("TERM") },
            kill: { child.record("KILL") },
            grace: 0.2,
            afterKill: 0.2
        )

        #expect(ended)
        #expect(child.signals.isEmpty)
    }
}
#endif
