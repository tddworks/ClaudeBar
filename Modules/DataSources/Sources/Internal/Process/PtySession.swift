#if canImport(Darwin) || canImport(Glibc)
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation

/// The two ends of an opened POSIX pty: `session` to read and write, `child`
/// for the program's standard files.
struct PtyEnds: Sendable {
    let session: Int32
    let child: Int32
}

/// A program running on a POSIX pty, the Mac's and Linux' alike: started by
/// `Foundation.Process` with the pty's child end as its standard input,
/// output and error, read without waiting from the session end, and ended
/// with `SIGTERM`, then `SIGKILL` after the launch's grace (`ChildTeardown`).
final class PtySession: TerminalSession, @unchecked Sendable {
    private let session: FileHandle
    private let child: FileHandle
    private let process: Process
    private let stopGrace: Duration?
    private let lock = NSLock()
    private var ended = false

    private init(session: FileHandle, child: FileHandle, process: Process, stopGrace: Duration?) {
        self.session = session
        self.child = child
        self.process = process
        self.stopGrace = stopGrace
    }

    /// Starts `launch` on `ends`. The ends are closed if it doesn't start.
    static func start(_ launch: TerminalLaunch, on ends: PtyEnds) throws -> PtySession {
        _ = fcntl(ends.session, F_SETFL, O_NONBLOCK)
        let session = FileHandle(fileDescriptor: ends.session, closeOnDealloc: true)
        let child = FileHandle(fileDescriptor: ends.child, closeOnDealloc: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: launch.executable)
        process.arguments = launch.arguments
        process.standardInput = child
        process.standardOutput = child
        process.standardError = child
        process.environment = launch.environment
        // The background monitoring loop binds `.utility`, so the spawned CLI
        // tree runs on efficiency cores / throttled, cutting idle heat (#204).
        process.qualityOfService = launch.qualityOfService
        if let directory = launch.directory {
            process.currentDirectoryURL = directory
        }

        do {
            try process.run()
        } catch {
            try? session.close()
            try? child.close()
            throw PseudoTerminalError.couldNotStart(error.localizedDescription)
        }
        return PtySession(session: session, child: child, process: process, stopGrace: launch.stopGrace)
    }

    func read() -> Data {
        var data = Data()
        var chunk = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = readBytes(session.fileDescriptor, &chunk, chunk.count)
            guard count > 0 else { break }
            data.append(contentsOf: chunk.prefix(count))
        }
        return data
    }

    func write(_ data: Data) throws {
        try session.write(contentsOf: data)
    }

    var isRunning: Bool { process.isRunning }

    var exitCode: Int32? { process.isRunning ? nil : process.terminationStatus }

    func end() {
        let first: Bool = lock.withLock {
            defer { ended = true }
            return !ended
        }
        guard first else { return }
        try? session.close()
        try? child.close()
        ChildTeardown.end(process, named: process.executableURL?.lastPathComponent ?? "terminal child", grace: stopGrace)
    }
}

/// The C library's `read`, named apart from `PtySession.read()`.
private func readBytes(_ fd: Int32, _ buffer: UnsafeMutableRawPointer, _ count: Int) -> Int {
    #if canImport(Darwin)
    Darwin.read(fd, buffer, count)
    #else
    Glibc.read(fd, buffer, count)
    #endif
}
#endif
