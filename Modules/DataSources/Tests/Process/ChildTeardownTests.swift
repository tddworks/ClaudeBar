import Testing
import Foundation
@testable import DataSources

/// Ending a child a fetch started has a bound (#550): a refresh's deadline
/// closes the CLI it started, and a child still there after it was killed
/// used to hold that close, the refresh, and every later one, on
/// "Syncing..." forever. The steps run on every platform; the real child is POSIX's.
@Suite(.timeLimit(.minutes(1)))
struct ChildTeardownTests {
    /// A child that is asked, then made, to stop, and never does.
    private final class StuckChild: @unchecked Sendable {
        private let lock = NSLock()
        private var asked: [String] = []
        var signals: [String] { lock.lock(); defer { lock.unlock() }; return asked }
        func record(_ signal: String) { lock.lock(); asked.append(signal); lock.unlock() }
    }

    @Test func `should give up on a child that outlives its kill, after asking and then making it stop`() {
        let child = StuckChild()
        let started = Date()

        let ended = ChildTeardown.end(
            named: "stuck child",
            isRunning: { true },
            terminate: { child.record("TERM") },
            kill: { child.record("KILL") },
            grace: .milliseconds(200),
            afterKill: .milliseconds(200)
        )

        #expect(!ended)
        #expect(child.signals == ["TERM", "KILL"])
        #expect(Date().timeIntervalSince(started) < 2)
    }

    #if canImport(Darwin) || canImport(Glibc)
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

        #expect(ChildTeardown.end(process, named: "test child", grace: .milliseconds(200)))
        try #require(!process.isRunning)
        // Only SIGKILL ended it: the request to stop alone did not.
        #expect(process.terminationReason == .uncaughtSignal)
        #expect(process.terminationStatus == SIGKILL)
    }
    #endif

    @Test func `should not signal a child that has already exited`() {
        let child = StuckChild()

        let ended = ChildTeardown.end(
            named: "ended child",
            isRunning: { false },
            terminate: { child.record("TERM") },
            kill: { child.record("KILL") },
            grace: .milliseconds(200),
            afterKill: .milliseconds(200)
        )

        #expect(ended)
        #expect(child.signals.isEmpty)
    }

    @Test func `should make a child stop at once, without asking, where its OS gives no grace`() {
        let child = StuckChild()

        let ended = ChildTeardown.end(
            named: "stuck child",
            isRunning: { true },
            terminate: { child.record("TERM") },
            kill: { child.record("KILL") },
            grace: nil,
            afterKill: .milliseconds(200)
        )

        #expect(!ended)
        #expect(child.signals == ["KILL"])
    }
}
