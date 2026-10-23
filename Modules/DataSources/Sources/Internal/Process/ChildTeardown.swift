import Diagnostics
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation

/// Ends a child a fetch started, within a bound (#550).
///
/// The child is asked to stop, made to after `grace`, and given `afterKill`
/// more to be gone. A child still there after that is left, logged by name:
/// a refresh's deadline closes the CLI it started, so waiting on such a child
/// without a bound held that refresh, and every later one joining it, on
/// "Syncing..." until a relaunch.
///
/// The steps are the same on every platform; what "ask" and "make" are is
/// the caller's: `SIGTERM` and `SIGKILL` on POSIX, ending the job on Windows.
/// How long the child is given once asked is its OS's answer
/// (`ChildLaunch.stopGrace`); with none, it is made to stop at once.
enum ChildTeardown {
    /// The steps over any child, so the bound holds whatever the child does.
    /// Answers whether it is gone; one still running is logged as `name`.
    @discardableResult
    static func end(
        named name: String,
        isRunning: () -> Bool,
        terminate: () -> Void,
        kill: () -> Void,
        grace: Duration?,
        afterKill: Duration
    ) -> Bool {
        guard isRunning() else { return true }
        if let grace {
            terminate()
            if waitForExit(isRunning, within: grace) { return true }
        }
        kill()
        if waitForExit(isRunning, within: afterKill) { return true }
        AppLog.probes.warning("\(name) was still running \(afterKill) after it was killed; leaving it so the fetch can end")
        return false
    }

    private static func waitForExit(_ isRunning: () -> Bool, within bound: Duration) -> Bool {
        // A monotonic clock: a wall-clock change mustn't stretch the bound.
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: bound)
        while isRunning() {
            guard clock.now < deadline else { return false }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return true
    }
}

#if canImport(Darwin) || canImport(Glibc)
extension ChildTeardown {
    /// Ends `process`: `SIGTERM`, then `SIGKILL` after `grace` (at once when
    /// `nil`). Answers whether it is gone.
    ///
    /// Nothing needs to wait for the exit to reap it: `Process` reaps its own
    /// child when it sees it end.
    @discardableResult
    static func end(_ process: Process, named name: String, grace: Duration?, afterKill: Duration = .seconds(2)) -> Bool {
        let pid = process.processIdentifier
        return end(
            named: "\(name) (pid \(pid))",
            isRunning: { process.isRunning },
            terminate: { process.terminate() },
            kill: { _ = kill(pid, SIGKILL) },
            grace: grace,
            afterKill: afterKill
        )
    }
}
#endif
