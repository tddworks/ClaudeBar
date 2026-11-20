import Foundation
import Mockable

/// Answers whether a process is still running on this Mac.
///
/// A Claude Code session that is killed outright (a crash, a force-quit
/// terminal) never sends `SessionEnd`; this is how `SessionMonitor` finds out.
@Mockable
public protocol ProcessLiveness: Sendable {
    func isRunning(processId: Int) -> Bool
}
