import Darwin
import Foundation

/// Executes CLI commands in a pseudo-terminal (PTY) to simulate interactive terminal behavior.
/// This is necessary because many CLI tools detect non-TTY environments and behave differently.
public struct PTYCommandRunner: Sendable {
    public struct Result: Sendable {
        public let text: String
        public let exitCode: Int32
    }

    public struct Options: Sendable {
        public var rows: UInt16
        public var cols: UInt16
        public var timeout: TimeInterval
        public var workingDirectory: URL?
        public var extraArgs: [String]
        public var sendOnSubstrings: [String: String]

        public init(
            rows: UInt16 = 50,
            cols: UInt16 = 160,
            timeout: TimeInterval = 20.0,
            workingDirectory: URL? = nil,
            extraArgs: [String] = [],
            sendOnSubstrings: [String: String] = [:]
        ) {
            self.rows = rows
            self.cols = cols
            self.timeout = timeout
            self.workingDirectory = workingDirectory
            self.extraArgs = extraArgs
            self.sendOnSubstrings = sendOnSubstrings
        }
    }

    public enum RunError: Error, LocalizedError, Sendable {
        case binaryNotFound(String)
        case launchFailed(String)
        case timedOut

        public var errorDescription: String? {
            switch self {
            case let .binaryNotFound(bin):
                "CLI '\(bin)' not found. Please install it and ensure it's on PATH."
            case let .launchFailed(msg):
                "Failed to launch process: \(msg)"
            case .timedOut:
                "PTY command timed out."
            }
        }
    }

    public init() {}

    /// Runs a command in a PTY and returns the captured output.
    public func run(
        binary: String,
        send script: String,
        options: Options = Options()
    ) throws -> Result {
        // Resolve binary path
        let resolved: String
        if FileManager.default.isExecutableFile(atPath: binary) {
            resolved = binary
        } else if let hit = Self.which(binary) {
            resolved = hit
        } else {
            throw RunError.binaryNotFound(binary)
        }

        // Create PTY
        var primaryFD: Int32 = -1
        var secondaryFD: Int32 = -1
        var win = winsize(ws_row: options.rows, ws_col: options.cols, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&primaryFD, &secondaryFD, nil, nil, &win) == 0 else {
            throw RunError.launchFailed("openpty failed")
        }

        // Make primary non-blocking
        _ = fcntl(primaryFD, F_SETFL, O_NONBLOCK)

        let primaryHandle = FileHandle(fileDescriptor: primaryFD, closeOnDealloc: true)
        let secondaryHandle = FileHandle(fileDescriptor: secondaryFD, closeOnDealloc: true)

        // Setup process
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: resolved)
        proc.arguments = options.extraArgs
        proc.standardInput = secondaryHandle
        proc.standardOutput = secondaryHandle
        proc.standardError = secondaryHandle
        proc.environment = Self.enrichedEnvironment()

        if let workingDirectory = options.workingDirectory {
            proc.currentDirectoryURL = workingDirectory
        }

        var cleanedUp = false
        var didLaunch = false

        func cleanup() {
            guard !cleanedUp else { return }
            cleanedUp = true

            try? primaryHandle.close()
            try? secondaryHandle.close()

            if didLaunch, proc.isRunning {
                proc.terminate()
                let waitDeadline = Date().addingTimeInterval(2.0)
                while proc.isRunning, Date() < waitDeadline {
                    usleep(100_000)
                }
                if proc.isRunning {
                    kill(proc.processIdentifier, SIGKILL)
                }
                proc.waitUntilExit()
            }
        }

        defer { cleanup() }

        try proc.run()
        didLaunch = true

        func send(_ text: String) throws {
            guard let data = text.data(using: .utf8) else { return }
            try primaryHandle.write(contentsOf: data)
        }

        let deadline = Date().addingTimeInterval(options.timeout)

        var buffer = Data()
        func readChunk() {
            while true {
                var tmp = [UInt8](repeating: 0, count: 8192)
                let n = Darwin.read(primaryFD, &tmp, tmp.count)
                if n > 0 {
                    buffer.append(contentsOf: tmp.prefix(n))
                    continue
                }
                break
            }
        }

        // Initial delay
        usleep(400_000)

        // Send the script
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            try send(trimmed)
            try send("\r")
        }

        // Auto-respond and read loop
        let sendNeedles = options.sendOnSubstrings.map { (needle: Data($0.key.utf8), keys: Data($0.value.utf8)) }
        var triggeredSends = Set<Data>()

        while Date() < deadline {
            readChunk()

            // Auto-respond to prompts
            for item in sendNeedles where !triggeredSends.contains(item.needle) {
                if buffer.range(of: item.needle) != nil {
                    try? primaryHandle.write(contentsOf: item.keys)
                    triggeredSends.insert(item.needle)
                }
            }

            if !proc.isRunning { break }
            usleep(60000)
        }

        guard let text = String(data: buffer, encoding: .utf8), !text.isEmpty else {
            throw RunError.timedOut
        }

        return Result(text: text, exitCode: proc.terminationStatus)
    }

    /// Locates a binary using the which command
    public static func which(_ tool: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = [tool]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = Self.effectivePATH()
        proc.environment = env
        let pipe = Pipe()
        proc.standardOutput = pipe
        try? proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !path.isEmpty else { return nil }
        return path
    }

    /// Returns an enriched PATH that includes common CLI installation locations
    private static func effectivePATH() -> String {
        let home = NSHomeDirectory()
        let common = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "\(home)/.local/bin",
            "\(home)/.bun/bin",
            "\(home)/.nvm/versions/node/*/bin",
            "/usr/bin",
            "/bin",
        ]
        let existing = ProcessInfo.processInfo.environment["PATH"] ?? ""
        return (common + [existing]).joined(separator: ":")
    }

    /// Returns an enriched environment for running CLI commands
    private static func enrichedEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = effectivePATH()
        env["HOME"] = env["HOME"] ?? NSHomeDirectory()
        env["TERM"] = env["TERM"] ?? "xterm-256color"
        env["COLORTERM"] = env["COLORTERM"] ?? "truecolor"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        env["CI"] = env["CI"] ?? "0"
        return env
    }
}
