import Darwin
import Foundation

/// The executable paths of the processes running now, read from the kernel
/// without starting a process.
enum RunningProcesses {
    static let system: @Sendable () -> [String] = {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        guard capacity > 64 else { return [] }
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size)))
        var paths: [String] = []
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        for pid in pids.prefix(max(0, count)) where pid > 0 {
            if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 {
                paths.append(String(cString: buffer))
            }
        }
        return paths
    }
}
