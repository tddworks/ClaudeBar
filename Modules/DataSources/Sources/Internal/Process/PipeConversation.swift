import Diagnostics
import Quotas
import Foundation
import Subprocess
import Synchronization

/// A newline-delimited conversation with a program on its input and output,
/// as a `jsonRpc` fetch holds with `codex app-server`. The same on every
/// platform: Subprocess starts the program, as the pipe runner does, so the
/// program gets its three pipes and none of the app's other handles. On
/// Windows, `Foundation.Process` hands a child every handle the app may pass
/// on, and one it got while an atomic write had its temporary file open kept
/// that write from moving the file into place for as long as it ran.
///
/// Subprocess scopes a run to a closure, so the conversation holds that run
/// in a task of its own: `send` queues a line for it, `receive` reads the
/// lines it printed, and `close` ends it, the OS's `ChildLaunch.teardown`
/// stopping the program.
final class PipeConversation: RPCTransport, @unchecked Sendable {
    private let outgoing: AsyncStream<Data>.Continuation
    private let received: AsyncThrowingStream<Data, any Error>.Continuation
    private let run: Task<Void, Never>
    private let closed = Mutex(false)
    /// Read only by `receive`, which the RPC client calls one at a time.
    private var lines: AsyncThrowingStream<Data, any Error>.Iterator

    init(executablePath: String, arguments: [String], environment: [String: String], directory: URL?,
         teardown: [TeardownStep]) {
        let (messages, outgoing) = AsyncStream<Data>.makeStream()
        let (output, received) = AsyncThrowingStream<Data, any Error>.makeStream()
        var options = PlatformOptions()
        options.teardownSequence = teardown
        #if os(macOS)
        // Both enums use Darwin QoS class values, but they are distinct Swift types.
        options.qualityOfService = PlatformOptions.QualityOfService(rawValue: FetchContext.qualityOfService.rawValue) ?? .default
        #endif
        let name = URL(fileURLWithPath: executablePath).lastPathComponent
        run = Task.detached {
            do {
                _ = try await Subprocess.run(
                    .path(.init(executablePath)),
                    arguments: Arguments(arguments),
                    environment: SubprocessSupport.environment(environment),
                    // Some CLIs (Codex 0.150+, #267) trust-check the directory
                    // they start in before answering anything, so the caller picks it.
                    workingDirectory: directory.map { .init($0.path) },
                    platformOptions: options,
                    input: .inputWriter,
                    output: .sequence,
                    error: .discarded
                ) { execution in
                    await withTaskGroup(of: Void.self) { group in
                        group.addTask {
                            for await message in messages {
                                do {
                                    _ = try await execution.standardInputWriter.write(Array(message))
                                } catch {
                                    // `send` only queued the line: the request
                                    // waiting on its answer hears it here.
                                    AppLog.probes.error("RPC transport: Failed to write to stdin: \(error.localizedDescription)")
                                    outgoing.finish()
                                    received.finish(throwing: UsageError.executionFailed("RPC transport write failed: \(error.localizedDescription)"))
                                    break
                                }
                            }
                            // Closing its input is the graceful exit for
                            // `codex app-server`: it sees the end and shuts down.
                            try? await execution.standardInputWriter.finish()
                        }
                        await Self.read(execution.standardOutput, into: received)
                        group.cancelAll()
                    }
                }
            } catch where !Task.isCancelled {
                AppLog.probes.error("RPC transport: Failed to start \(executablePath): \(error.localizedDescription)")
                received.finish(throwing: UsageError.executionFailed("Failed to start \(name): \(error.localizedDescription)"))
            } catch {}
            // Ended, by `close` or on its own: a later `send` fails, a later
            // `receive` ends.
            outgoing.finish()
            received.finish()
        }
        self.outgoing = outgoing
        self.received = received
        self.lines = output.makeAsyncIterator()
    }

    func send(_ data: Data) throws {
        var message = data
        message.append(0x0A)
        if case .terminated = outgoing.yield(message) {
            throw UsageError.executionFailed("RPC transport write failed: the conversation has ended")
        }
    }

    func receive() async throws -> Data {
        guard let line = try await lines.next() else { throw UsageError.executionFailed("Process closed unexpectedly") }
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
        outgoing.finish()
        received.finish()
        // Asked, made, then left (#550): cancelling the run tears the program
        // down by the OS's steps, and this close, the deadline's, doesn't wait
        // on a child that outlives the end.
        run.cancel()
    }

    /// The program's output, a line at a time without its line ending, until
    /// it ends; a child's own children still holding the output keep it open
    /// until they exit.
    private static func read(_ output: SubprocessOutputSequence,
                             into received: AsyncThrowingStream<Data, any Error>.Continuation) async {
        var buffer = Data()
        do {
            for try await chunk in output {
                chunk.withUnsafeBytes { buffer.append(contentsOf: $0) }
                while let newline = buffer.firstIndex(of: 0x0A) {
                    var line = buffer[buffer.startIndex..<newline]
                    buffer.removeSubrange(buffer.startIndex...newline)
                    if line.last == 0x0D { line = line.dropLast() }
                    if !line.isEmpty { received.yield(Data(line)) }
                }
            }
        } catch {}
    }
}
