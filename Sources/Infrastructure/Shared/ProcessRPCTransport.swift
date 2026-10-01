import Darwin
import Domain
import Foundation

/// RPC transport that communicates via Process stdin/stdout pipes.
/// This is excluded from code coverage as it's a pure adapter for system interaction.
///
/// Deliberately still on `Foundation.Process`: Subprocess's `run` is scoped to a
/// closure, so a long-lived bidirectional transport built on it would need an
/// AsyncStream bridge plus an async `send`, cascading through the RPC client and
/// its test doubles. The defects that mattered here (an EPIPE trap on write, an
/// unreaped child on close) are fixed directly below instead.
public final class ProcessRPCTransport: RPCTransport, @unchecked Sendable {
    private let process: Process
    private let stdinPipe: Pipe
    private let stdoutPipe: Pipe

    public init(executable: String, arguments: [String], environment: [String: String]? = nil) throws {
        self.process = Process()
        self.stdinPipe = Pipe()
        self.stdoutPipe = Pipe()

        guard let executablePath = BinaryLocator.which(executable) else {
            AppLog.probes.error("RPC transport: '\(executable)' not found in PATH")
            AppLog.probes.debug("Shell PATH: \(BinaryLocator.shellPath())")
            throw ProbeError.cliNotFound(executable)
        }
        
        AppLog.probes.debug("RPC transport: Found '\(executable)' at: \(executablePath)")

        var env = environment ?? ProcessInfo.processInfo.environment
        env["PATH"] = BinaryLocator.shellPath()

        process.environment = env
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            AppLog.probes.error("RPC transport: Failed to start '\(executable)' at \(executablePath): \(error.localizedDescription)")
            throw ProbeError.executionFailed("Failed to start \(executable): \(error.localizedDescription)")
        }
    }

    public func send(_ data: Data) throws {
        // `FileHandle.write(_:)` traps on EPIPE, which crashes the whole app if
        // the child already exited. The throwing variant surfaces it as an error
        // the RPC client can fall back from.
        do {
            var message = data
            message.append(0x0A)  // newline-delimited JSON-RPC
            try stdinPipe.fileHandleForWriting.write(contentsOf: message)
        } catch {
            AppLog.probes.error("RPC transport: Failed to write to stdin: \(error.localizedDescription)")
            throw ProbeError.executionFailed("RPC transport write failed: \(error.localizedDescription)")
        }
    }

    public func receive() async throws -> Data {
        for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
            guard !line.isEmpty, let data = line.data(using: .utf8) else {
                continue
            }
            return data
        }
        throw ProbeError.executionFailed("Process closed unexpectedly")
    }

    public func close() {
        // Closing stdin is the graceful exit for `codex app-server`: it sees EOF
        // and shuts down on its own, without needing a signal.
        try? stdinPipe.fileHandleForWriting.close()

        if process.isRunning {
            process.terminate()

            // Bounded wait, then escalate. Mirrors InteractiveRunner's teardown.
            let deadline = Date().addingTimeInterval(2.0)
            while process.isRunning, Date() < deadline {
                usleep(50_000)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }

        // Reap the child. Without this it lingers as a zombie for the lifetime
        // of the app, since nothing else ever waits on it.
        process.waitUntilExit()
        try? stdoutPipe.fileHandleForReading.close()
    }
}
