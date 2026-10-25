import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A file a test writes and then runs.
///
/// On POSIX a short-lived `sh` writes it, never the test process. Tests run in
/// parallel and start programs all the time: a child started while this
/// process held the file open for writing keeps that handle until it execs,
/// and running the file meanwhile fails with `ETXTBSY` ("text file busy").
/// On Linux the terminal suites failed so about once in 15 runs.
enum ExecutableFile {
    static func write(_ text: String, to url: URL) throws {
        #if os(Windows)
        try Data(text.utf8).write(to: url)
        #else
        // `printf` is the shell's own, so the file is closed before `chmod` starts.
        let arguments = ["/bin/sh", "-c", #"printf '%s' "$2" > "$1" && chmod 755 "$1""#, "sh", url.path, text]
        let argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        // Its own environment: other tests `setenv` while this runs, and
        // `environ` read meanwhile can point at freed memory (`EFAULT`).
        let envp: [UnsafeMutablePointer<CChar>?] = [strdup("PATH=/usr/bin:/bin"), nil]
        defer { (argv + envp).forEach { free($0) } }
        var pid: pid_t = 0
        let spawned = posix_spawn(&pid, "/bin/sh", nil, nil, argv, envp)
        guard spawned == 0 else { throw POSIXError(POSIXErrorCode(rawValue: spawned) ?? .EIO) }
        var status: Int32 = 0
        var waited = waitpid(pid, &status, 0)
        while waited == -1 && errno == EINTR { waited = waitpid(pid, &status, 0) }
        // Only a reaped child's status says the file was written.
        guard waited == pid else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard status == 0 else { throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path]) }
        #endif
    }
}
