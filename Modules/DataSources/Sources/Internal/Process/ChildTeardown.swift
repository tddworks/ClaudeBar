#if canImport(Darwin) || canImport(Glibc)
import Diagnostics
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation

/// Ends a child a fetch started, within a bound (#550).
///
/// The child is asked to stop (`SIGTERM`), made to after `grace` (`SIGKILL`),
/// and given `afterKill` more to be gone. A child still there after that is
/// left, logged by name and pid: a refresh's deadline closes the CLI it
/// started, so waiting on such a child without a bound held that refresh,
/// and every later one joining it, on "Syncing..." until a relaunch.
///
/// Nothing needs to wait for the exit to reap it: `Process` reaps its own
/// child when it sees it end.
enum ChildTeardown {
    /// Ends `process`. Answers whether it is gone.
    @discardableResult
    static func end(_ process: Process, named name: String, grace: TimeInterval = 2, afterKill: TimeInterval = 2) -> Bool {
        let pid = process.processIdentifier
        let ended = end(
            isRunning: { process.isRunning },
            terminate: { process.terminate() },
            kill: { _ = kill(pid, SIGKILL) },
            grace: grace,
            afterKill: afterKill
        )
        if !ended {
            AppLog.probes.warning("\(name) (pid \(pid)) was still running \(Int(afterKill))s after SIGKILL; leaving it so the fetch can end")
        }
        return ended
    }

    /// The same steps over any child, so the bound holds whatever the child does.
    static func end(
        isRunning: () -> Bool,
        terminate: () -> Void,
        kill: () -> Void,
        grace: TimeInterval,
        afterKill: TimeInterval
    ) -> Bool {
        guard isRunning() else { return true }
        terminate()
        if waitForExit(isRunning, within: grace) { return true }
        kill()
        return waitForExit(isRunning, within: afterKill)
    }

    private static func waitForExit(_ isRunning: () -> Bool, within seconds: TimeInterval) -> Bool {
        // A monotonic clock: a wall-clock change mustn't stretch the bound.
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(seconds))
        while isRunning() {
            guard clock.now < deadline else { return false }
            usleep(20_000)
        }
        return true
    }
}
#endif
