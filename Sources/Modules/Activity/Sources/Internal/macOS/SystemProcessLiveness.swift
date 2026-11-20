#if os(macOS)
import Foundation
import Quotas
import DataSources
import Providers

/// Asks the kernel whether a process exists, without signalling it.
struct SystemProcessLiveness: ProcessLiveness {
    init() {}

    func isRunning(processId: Int) -> Bool {
        guard let pid = pid_t(exactly: processId), pid > 0 else { return false }
        // Signal 0 delivers nothing but still checks the process exists.
        // EPERM means it exists but belongs to someone else: still running.
        return kill(pid, 0) == 0 || errno == EPERM
    }
}
#endif
