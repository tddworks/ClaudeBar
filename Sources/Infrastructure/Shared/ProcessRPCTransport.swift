import Foundation
import Domain

/// RPC transport that communicates via Process stdin/stdout pipes.
/// This is excluded from code coverage as it's a pure adapter for system interaction.
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
        stdinPipe.fileHandleForWriting.write(data)
        stdinPipe.fileHandleForWriting.write(Data([0x0A])) // newline
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
        if process.isRunning {
            process.terminate()
        }
    }
}
