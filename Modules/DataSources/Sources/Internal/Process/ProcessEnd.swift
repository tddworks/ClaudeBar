#if canImport(Darwin) || canImport(Glibc)
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation

extension Process {
    /// A launched program's exit status, `nil` while it runs, as the kernel
    /// has it. Linux' Foundation notices a child's end up to seconds after it
    /// ended when many programs run at once, and says it is still running till
    /// then; the kernel is asked with `WNOWAIT`, so the child is left for
    /// Foundation to reap.
    var endStatus: Int32? {
        guard isRunning else { return terminationStatus }
        var info = siginfo_t()
        guard waitid(P_PID, id_t(processIdentifier), &info, WEXITED | WNOHANG | WNOWAIT) == 0 else {
            // Foundation reaped it in between.
            return isRunning ? nil : terminationStatus
        }
        #if canImport(Darwin)
        let (pid, status) = (info.si_pid, info.si_status)
        #else
        let (pid, status) = (info._sifields._sigchld.si_pid, info._sifields._sigchld.si_status)
        #endif
        return pid == processIdentifier ? status : nil
    }
}
#endif
