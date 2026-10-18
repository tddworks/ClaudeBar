#if os(Windows)
import Diagnostics
import Foundation
import Quotas
import WinSDK

/// Windows' `Processes`: a CLI found on `PATH` with `PATHEXT`, programs run
/// in the app's environment, a child ended with `TerminateProcess`, the
/// kernel's process list, and the person's PowerShell profile.
struct WindowsProcesses: Processes {
    func locate(_ cli: String) -> String? {
        PathBinaryLocator().locate(cli)
    }

    func runner(_ change: ProcessEnvironment) -> any CLIExecutor {
        PipeCLIExecutor(change: change, facts: Self.facts)
    }

    func converse(_ executable: String, _ arguments: [String], _ environment: [String: String]?,
                  _ directory: URL?) throws -> any RPCTransport {
        guard let path = locate(executable) else {
            AppLog.probes.error("RPC transport: '\(executable)' not found on PATH")
            throw UsageError.cliNotFound(executable)
        }
        return try PipeConversation(executablePath: path, arguments: arguments,
                                    environment: environment ?? ProcessInfo.processInfo.environment,
                                    directory: directory, end: Self.facts.end)
    }

    func running() -> [String] {
        Self.executablePaths()
    }

    // `CreateProcess` runs a `.cmd` or `.bat` through cmd itself, with its
    // path quoted, so spaces, `(x86)` and `&` in it are kept. A person's
    // script is run as the file it is.
    func script(_ path: String) -> [String] {
        [path]
    }

    // `-Command` loads the person's PowerShell profile, the closest Windows
    // has to a login shell's rc files.
    func loginVariable(_ variable: String) -> [String] {
        let print = "'\(LoginShellEnvironment.beginMarker)' + $env:\(variable) + '\(LoginShellEnvironment.endMarker)'"
        return ["powershell.exe", "-NoLogo", "-NonInteractive", "-Command", print]
    }

    static let facts = PipeFacts(
        locate: { PathBinaryLocator().locate($0) },
        environment: { _, change in environment(change) },
        // `terminate()` is `TerminateProcess`: the child ends at once.
        end: { process in if process.isRunning { process.terminate() } }
    )

    /// The app's environment with the call's changes. Windows' variable names
    /// ignore case, so a change replaces or removes a name however it is spelled.
    static func environment(_ change: ProcessEnvironment,
                            base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        let removed = Set(change.unset.map { $0.uppercased() }).union(change.set.keys.map { $0.uppercased() })
        var environment = base.filter { !removed.contains($0.key.uppercased()) }
        environment.merge(change.set) { _, value in value }
        return environment
    }

    /// The executable paths of the processes running now. A process this user
    /// can't open (a service, the system) is left out.
    static func executablePaths() -> [String] {
        var ids = [DWORD](repeating: 0, count: 4096)
        var returned: DWORD = 0
        while true {
            let size = DWORD(ids.count * MemoryLayout<DWORD>.size)
            guard K32EnumProcesses(&ids, size, &returned) else { return [] }
            if returned < size { break }
            ids = [DWORD](repeating: 0, count: ids.count * 2)
        }
        var paths: [String] = []
        var buffer = [WCHAR](repeating: 0, count: 32_768)
        for id in ids.prefix(Int(returned) / MemoryLayout<DWORD>.size) where id != 0 {
            guard let process = OpenProcess(DWORD(PROCESS_QUERY_LIMITED_INFORMATION), false, id) else { continue }
            defer { CloseHandle(process) }
            var length = DWORD(buffer.count)
            if QueryFullProcessImageNameW(process, 0, &buffer, &length) {
                paths.append(String(decoding: buffer.prefix(Int(length)), as: UTF16.self))
            }
        }
        return paths
    }
}
#endif
