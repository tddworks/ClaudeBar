#if os(Windows)
import Diagnostics
import Foundation
import WinSDK

/// Windows' terminal: a pseudo console (ConPTY), the CLI created attached to
/// it. A session's environment is a program's (`WindowsProcesses`): Windows
/// has no login shell `PATH` and reads no `LANG`.
struct ConPty: PseudoTerminal {
    func start(_ launch: TerminalLaunch) throws -> any TerminalSession {
        try ConPtySession.start(launch)
    }

    func sessionPath() -> String? { nil }

    var fallbackLocale: String? { nil }
}

/// A CLI running in a pseudo console.
///
/// - **Start.** `CreatePseudoConsole` over two pipes, then `CreateProcessW`
///   with the console in `STARTUPINFOEX` and null standard handles: without
///   them, an app whose own standard files are redirected (a GUI app, a test
///   runner) hands those to the child, which then writes past the console. A
///   `.cmd` CLI starts as a program over pipes does, through cmd with its
///   path quoted. The child starts suspended and joins a job before it runs,
///   so every process it starts (`claude.cmd` starts `node`) ends with it.
/// - **Read.** A thread drains the console's output into a buffer `read()`
///   empties, so the console never waits on a full pipe — not even while it
///   closes, which waits for its last frame to be read.
/// - **End.** `ChildTeardown`'s steps with the launch's grace, which
///   `WindowsProcesses.stopGrace` leaves out: Windows' graceful step attaches
///   to the child's console, which a GUI app shouldn't do. The job is ended,
///   then the console closes, which ends the reader.
final class ConPtySession: TerminalSession, @unchecked Sendable {
    private let console: HPCON
    private let input: HANDLE
    private let output: HANDLE
    private let process: HANDLE
    private let job: HANDLE
    private let name: String
    private let stopGrace: Duration?

    private let lock = NSLock()
    private var pending = Data()
    private var lastSeen: ContinuousClock.Instant
    private var exitSeen: ContinuousClock.Instant?
    private var readerEnded = false
    private var ended = false

    /// The console paints asynchronously, after the program wrote: what the
    /// program drew before it ended keeps arriving for a moment after. The
    /// session counts as running until it has been quiet this long since then.
    private static let lastFrameQuiet: Duration = .milliseconds(300)

    private init(console: HPCON, input: HANDLE, output: HANDLE, process: HANDLE, job: HANDLE, name: String,
                 stopGrace: Duration?) {
        self.console = console
        self.input = input
        self.output = output
        self.process = process
        self.job = job
        self.name = name
        self.stopGrace = stopGrace
        self.lastSeen = ContinuousClock.now
        Thread.detachNewThread { [self] in self.drain() }
    }

    static func start(_ launch: TerminalLaunch) throws -> ConPtySession {
        var inputRead: HANDLE?
        var inputWrite: HANDLE?
        var outputRead: HANDLE?
        var outputWrite: HANDLE?
        guard CreatePipe(&inputRead, &inputWrite, nil, 0) else { throw PseudoTerminalError.couldNotOpen }
        guard CreatePipe(&outputRead, &outputWrite, nil, 0) else {
            CloseHandle(inputRead); CloseHandle(inputWrite)
            throw PseudoTerminalError.couldNotOpen
        }
        var opened: HPCON?
        let result = CreatePseudoConsole(COORD(X: SHORT(launch.cols), Y: SHORT(launch.rows)), inputRead, outputWrite, 0, &opened)
        // The console holds its own copies of its ends.
        CloseHandle(inputRead)
        CloseHandle(outputWrite)
        guard result == S_OK, let console = opened, let input = inputWrite, let output = outputRead else {
            CloseHandle(inputWrite); CloseHandle(outputRead)
            throw PseudoTerminalError.couldNotOpen
        }

        let child: (process: HANDLE, job: HANDLE)
        do {
            child = try createProcess(launch, attachedTo: console)
        } catch {
            ClosePseudoConsole(console)
            CloseHandle(input)
            CloseHandle(output)
            throw error
        }
        let name = URL(fileURLWithPath: launch.executable).lastPathComponent
        return ConPtySession(console: console, input: input, output: output,
                             process: child.process, job: child.job, name: name, stopGrace: launch.stopGrace)
    }

    // MARK: - The session

    func read() -> Data {
        lock.withLock {
            defer { pending = Data() }
            return pending
        }
    }

    func write(_ data: Data) throws {
        let bytes = [UInt8](data)
        var offset = 0
        while offset < bytes.count {
            var written: DWORD = 0
            let ok = bytes.withUnsafeBytes {
                WriteFile(input, $0.baseAddress! + offset, DWORD($0.count - offset), &written, nil)
            }
            guard ok, written > 0 else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSUnderlyingErrorKey: Win32Failure(code: GetLastError())])
            }
            offset += Int(written)
        }
    }

    var isRunning: Bool {
        let alive = WaitForSingleObject(process, 0) == WAIT_TIMEOUT
        return lock.withLock {
            if alive { return true }
            if readerEnded { return false }
            let now = ContinuousClock.now
            let exited = exitSeen ?? now
            exitSeen = exited
            return now - max(exited, lastSeen) < Self.lastFrameQuiet
        }
    }

    var exitCode: Int32? {
        guard WaitForSingleObject(process, 0) == WAIT_OBJECT_0 else { return nil }
        var code: DWORD = 0
        guard GetExitCodeProcess(process, &code) else { return nil }
        return Int32(bitPattern: code)
    }

    func end() {
        let first: Bool = lock.withLock {
            defer { ended = true }
            return !ended
        }
        guard first else { return }
        ChildTeardown.end(
            named: name,
            isRunning: { WaitForSingleObject(process, 0) == WAIT_TIMEOUT },
            // Nothing a GUI app should send asks a console child to stop.
            terminate: {},
            kill: { TerminateJobObject(job, 1) },
            grace: stopGrace,
            afterKill: .seconds(2)
        )
        ClosePseudoConsole(console)
        CloseHandle(input)
        CloseHandle(process)
        CloseHandle(job)
    }

    // MARK: - Reading

    /// Reads the console's output until it closes, then closes its end.
    private func drain() {
        var chunk = [UInt8](repeating: 0, count: 8192)
        while true {
            var count: DWORD = 0
            let ok = chunk.withUnsafeMutableBytes { ReadFile(output, $0.baseAddress, DWORD($0.count), &count, nil) }
            guard ok, count > 0 else { break }
            lock.withLock {
                pending.append(contentsOf: chunk.prefix(Int(count)))
                lastSeen = ContinuousClock.now
            }
        }
        CloseHandle(output)
        lock.withLock { readerEnded = true }
    }

    // MARK: - Starting

    /// Creates the program suspended, attached to `console`, joins it to a job
    /// that ends its whole tree, and lets it run.
    private static func createProcess(_ launch: TerminalLaunch, attachedTo console: HPCON) throws -> (process: HANDLE, job: HANDLE) {
        var size: SIZE_T = 0
        _ = InitializeProcThreadAttributeList(nil, 1, 0, &size)
        let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { storage.deallocate() }
        let attributes = LPPROC_THREAD_ATTRIBUTE_LIST(storage)
        guard InitializeProcThreadAttributeList(attributes, 1, 0, &size) else {
            throw PseudoTerminalError.couldNotStart("InitializeProcThreadAttributeList failed (\(GetLastError()))")
        }
        defer { DeleteProcThreadAttributeList(attributes) }
        // PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE, a macro the SDK module doesn't carry.
        let pseudoConsole: DWORD_PTR = 0x0002_0016
        guard UpdateProcThreadAttribute(attributes, 0, pseudoConsole, console, SIZE_T(MemoryLayout<HPCON>.size), nil, nil) else {
            throw PseudoTerminalError.couldNotStart("UpdateProcThreadAttribute failed (\(GetLastError()))")
        }

        var startup = STARTUPINFOEXW()
        startup.StartupInfo.cb = DWORD(MemoryLayout<STARTUPINFOEXW>.size)
        startup.lpAttributeList = attributes
        startup.StartupInfo.dwFlags = DWORD(STARTF_USESTDHANDLES)

        var commandLine = Array(Self.commandLine(launch.executable, launch.arguments).utf16) + [0]
        var environment = Self.environmentBlock(launch.environment)
        let directory = launch.directory.map { Array(Self.windowsPath($0.path).utf16) + [0] }
        var flags = DWORD(EXTENDED_STARTUPINFO_PRESENT) | DWORD(CREATE_UNICODE_ENVIRONMENT) | DWORD(CREATE_SUSPENDED)
        // The background monitoring loop's fetches stay out of the way (#204).
        if launch.qualityOfService == .utility || launch.qualityOfService == .background {
            flags |= DWORD(BELOW_NORMAL_PRIORITY_CLASS)
        }

        var information = PROCESS_INFORMATION()
        let created = withUnsafeMutablePointer(to: &startup) { pointer in
            pointer.withMemoryRebound(to: STARTUPINFOW.self, capacity: 1) { startupInfo in
                environment.withUnsafeMutableBufferPointer { block in
                    if var directory {
                        return directory.withUnsafeMutableBufferPointer { folder in
                            CreateProcessW(nil, &commandLine, nil, nil, false, flags, block.baseAddress, folder.baseAddress, startupInfo, &information)
                        }
                    }
                    return CreateProcessW(nil, &commandLine, nil, nil, false, flags, block.baseAddress, nil, startupInfo, &information)
                }
            }
        }
        guard created, let process = information.hProcess, let thread = information.hThread else {
            throw PseudoTerminalError.couldNotStart("CreateProcessW failed (\(GetLastError()))")
        }
        defer { CloseHandle(thread) }

        guard let job = CreateJobObjectW(nil, nil) else {
            TerminateProcess(process, 1)
            CloseHandle(process)
            throw PseudoTerminalError.couldNotStart("CreateJobObjectW failed (\(GetLastError()))")
        }
        var limits = JOBOBJECT_EXTENDED_LIMIT_INFORMATION()
        limits.BasicLimitInformation.LimitFlags = DWORD(JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE)
        let limited = SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits,
                                              DWORD(MemoryLayout<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>.size))
        guard limited, AssignProcessToJobObject(job, process) else {
            let code = GetLastError()
            TerminateProcess(process, 1)
            CloseHandle(process)
            CloseHandle(job)
            throw PseudoTerminalError.couldNotStart("joining the job failed (\(code))")
        }
        ResumeThread(thread)
        return (process, job)
    }

    /// The command line `CreateProcessW` parses back into `executable` and
    /// `arguments`, each quoted as the C runtime reads it.
    static func commandLine(_ executable: String, _ arguments: [String]) -> String {
        (["\"\(windowsPath(executable))\""] + arguments.map(quoted)).joined(separator: " ")
    }

    /// One argument as the C runtime's `CommandLineToArgvW` rules read it back:
    /// bare when it needs nothing, else in quotes with its quotes and the
    /// backslashes before them escaped.
    static func quoted(_ argument: String) -> String {
        guard argument.isEmpty || argument.contains(where: { " \t\n\u{0B}\"".contains($0) }) else { return argument }
        var result = "\""
        var backslashes = 0
        for character in argument {
            if character == "\\" {
                backslashes += 1
                continue
            }
            if character == "\"" {
                result += String(repeating: "\\", count: backslashes * 2 + 1) + "\""
            } else {
                result += String(repeating: "\\", count: backslashes) + String(character)
            }
            backslashes = 0
        }
        return result + String(repeating: "\\", count: backslashes * 2) + "\""
    }

    /// A path with Windows' separator: cmd, which starts a `.cmd` CLI, reads a
    /// `/` as a switch.
    static func windowsPath(_ path: String) -> String {
        var path = path.replacingOccurrences(of: "/", with: "\\")
        // Foundation may write a drive path as `\C:\...`.
        if path.hasPrefix("\\"), path.dropFirst().dropFirst().first == ":" { path.removeFirst() }
        return path
    }

    /// `KEY=value` strings, each ended by a null and the block by another,
    /// sorted by name ignoring case, as `CreateProcessW` wants them.
    static func environmentBlock(_ environment: [String: String]) -> [WCHAR] {
        let entries = environment.sorted { $0.key.uppercased() < $1.key.uppercased() }
        var block: [WCHAR] = []
        for (key, value) in entries {
            block += Array("\(key)=\(value)".utf16) + [0]
        }
        // An empty block still ends in two nulls.
        return block.isEmpty ? [0, 0] : block + [0]
    }
}

/// A Win32 error code, carried under a thrown error.
private struct Win32Failure: Error {
    let code: DWORD
}
#endif
