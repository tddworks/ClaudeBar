import Foundation
import Domain

/// Asks the kernel whether a process exists, without signalling it.
public struct SystemProcessLiveness: ProcessLiveness {
    public init() {}

    public func isRunning(processId: Int) -> Bool {
        guard let pid = pid_t(exactly: processId), pid > 0 else { return false }
        // Signal 0 delivers nothing but still checks the process exists.
        // EPERM means it exists but belongs to someone else: still running.
        return kill(pid, 0) == 0 || errno == EPERM
    }
}
