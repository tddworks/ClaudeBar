import Foundation

/// One thread for a test's tasks, which run on it one after another in the
/// order they were started, as on a pool whose every other thread is taken.
/// A test runs its work under `withTaskExecutorPreference`; `hold(for:)`
/// keeps the thread from the tasks started after it, as other work on a
/// busy pool does.
final class BusyThread: TaskExecutor, @unchecked Sendable {
    private let queue = DispatchQueue(label: "BusyThread")

    /// Runs `job` on the thread, after the tasks started before it.
    func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        queue.async { job.runSynchronously(on: self.asUnownedTaskExecutor()) }
    }

    /// Keeps the thread for `seconds`, once the tasks started before this
    /// call have had their turn.
    func hold(for seconds: TimeInterval) {
        queue.async { Thread.sleep(forTimeInterval: seconds) }
    }
}
