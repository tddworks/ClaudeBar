#if os(Linux)
import Foundation
import Glibc

// glibc's pty calls are libc's to answer, but Swift's Glibc modulemap carries
// none of them (MODULAR_DESIGN §10, Open), so they are declared by name and
// linked from libc.
@_silgen_name("posix_openpt") private func posix_openpt(_ oflag: Int32) -> Int32
@_silgen_name("grantpt") private func grantpt(_ fd: Int32) -> Int32
@_silgen_name("unlockpt") private func unlockpt(_ fd: Int32) -> Int32
@_silgen_name("ptsname_r") private func ptsname_r(_ fd: Int32, _ buf: UnsafeMutablePointer<CChar>!, _ length: Int) -> Int32

/// Linux' pty: `posix_openpt` on the session's end, the slave opened for the
/// child and sized as asked, and its program started on it as `PtySession`
/// does. A session's `PATH` is a program's (`LinuxProcesses`), with the tool
/// folders a service's minimal one misses.
struct LinuxPty: PseudoTerminal {
    func start(_ launch: TerminalLaunch) throws -> any TerminalSession {
        try PtySession.start(launch, on: open(rows: launch.rows, cols: launch.cols))
    }

    private func open(rows: UInt16, cols: UInt16) throws -> PtyEnds {
        let session = posix_openpt(O_RDWR | O_NOCTTY)
        guard session >= 0 else { throw PseudoTerminalError.couldNotOpen }
        guard grantpt(session) == 0, unlockpt(session) == 0 else {
            close(session)
            throw PseudoTerminalError.couldNotOpen
        }
        var name = [CChar](repeating: 0, count: 128)
        guard ptsname_r(session, &name, name.count) == 0 else {
            close(session)
            throw PseudoTerminalError.couldNotOpen
        }
        let child = Glibc.open(name, O_RDWR | O_NOCTTY)
        guard child >= 0 else {
            close(session)
            throw PseudoTerminalError.couldNotOpen
        }
        var size = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(child, UInt(TIOCSWINSZ), &size)
        return PtyEnds(session: session, child: child)
    }

    func sessionPath() -> String? { nil }

    // `en_US.UTF-8` may not be generated on a Linux machine; `C.UTF-8` is
    // built into glibc.
    var fallbackLocale: String? { "C.UTF-8" }
}
#endif
