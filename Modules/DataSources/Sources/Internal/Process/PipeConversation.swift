import Diagnostics
import Quotas
import Foundation
import Synchronization

/// A newline-delimited conversation with a program on its input and output,
/// as a `jsonRpc` fetch holds with `codex app-server`. The same on every
/// platform: `Foundation.Process` starts the program, and its output is read
/// on a thread of its own, since `FileHandle.bytes` is Apple's Foundation
/// only. The OS's `ChildLaunch.end` stops the program.
///
/// Still on `Foundation.Process`, not Subprocess: Subprocess's `run` is
/// scoped to a closure, so a long-lived conversation built on it would need
/// an async `send` throughout the RPC client and its test doubles.
final class PipeConversation: RPCTransport, @unchecked Sendable {
    private let process: Process
    private let input: FileHandle
    private let end: @Sendable (Process) -> Void
    private let closed = Mutex(false)
    /// Read only by `receive`, which the RPC client calls one at a time.
    private var lines: AsyncStream<Data>.Iterator

    init(executablePath: String, arguments: [String], environment: [String: String], directory: URL?,
         end: @escaping @Sendable (Process) -> Void) throws {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = environment
        // Some CLIs (Codex 0.150+, #267) trust-check the directory they start
        // in before answering anything, so the caller picks it.
        process.currentDirectoryURL = directory
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            AppLog.probes.error("RPC transport: Failed to start \(executablePath): \(error.localizedDescription)")
            throw UsageError.executionFailed("Failed to start \(URL(fileURLWithPath: executablePath).lastPathComponent): \(error.localizedDescription)")
        }
        self.process = process
        self.input = input.fileHandleForWriting
        self.end = end
        self.lines = Self.read(output.fileHandleForReading).makeAsyncIterator()
    }

    func send(_ data: Data) throws {
        // `FileHandle.write(_:)` traps on a broken pipe, which would crash the
        // app if the child already exited; the throwing variant is an error
        // the RPC client can fall back from.
        do {
            var message = data
            message.append(0x0A)
            try input.write(contentsOf: message)
        } catch {
            AppLog.probes.error("RPC transport: Failed to write to stdin: \(error.localizedDescription)")
            throw UsageError.executionFailed("RPC transport write failed: \(error.localizedDescription)")
        }
    }

    func receive() async throws -> Data {
        guard let line = await lines.next() else { throw UsageError.executionFailed("Process closed unexpectedly") }
        return line
    }

    func close() {
        // The deadline, a cancelled refresh and the fetch's own cleanup may
        // all close it, even at once; only the first does the work.
        let first = closed.withLock { wasClosed in
            defer { wasClosed = true }
            return !wasClosed
        }
        guard first else { return }
        // Closing its input is the graceful exit for `codex app-server`: it
        // sees the end and shuts down on its own.
        try? input.close()
        // Asked, made, then left (#550): this close is the deadline's, so it
        // can't wait on a child that outlives the end.
        end(process)
    }

    /// The program's output, a line at a time without its line ending, read
    /// until the end. The reading thread owns `handle` and closes it at the
    /// end, so nothing closes it under a read; a child's own children still
    /// holding the output keep it open until they exit.
    private static func read(_ handle: FileHandle) -> AsyncStream<Data> {
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        Thread.detachNewThread {
            var buffer = Data()
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    var line = buffer[buffer.startIndex..<newline]
                    buffer.removeSubrange(buffer.startIndex...newline)
                    if line.last == 0x0D { line = line.dropLast() }
                    if !line.isEmpty { continuation.yield(Data(line)) }
                }
            }
            try? handle.close()
            continuation.finish()
        }
        return stream
    }
}
