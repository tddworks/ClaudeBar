import Foundation

/// Runs `work`, which blocks the thread it runs on, on a thread of its own,
/// and waits for it without holding a thread of the cooperative pool.
///
/// Swift Testing runs the tests at once on that pool, which has a thread per
/// core: four on a CI runner. A test that blocks one for seconds, a run in a
/// real terminal or a script left to run to its deadline, holds it from every
/// other test, and a few of them at once stop them all. A test that times
/// something then counts seconds it never ran: on CI the suites stalled for
/// 14 to 40 s, and JSON-RPC deadline tests failed on Linux and Windows (#686).
/// The app keeps its blocking runs off the pool the same way (`DefaultCLIExecutor`).
func onItsOwnThread<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        Thread { continuation.resume(with: Result { try work() }) }.start()
    }
}
