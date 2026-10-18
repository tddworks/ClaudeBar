#if os(Windows)
import Foundation
import WinSDK

/// What Windows answers about programs: a CLI found on `PATH` with
/// `PATHEXT`, a script run as the file itself, a variable read through the
/// person's PowerShell profile, a child in the app's environment ended with
/// `TerminateProcess`, and the kernel's process list.
struct WindowsProcesses: InstalledPrograms, ScriptStart, LoginShell, ChildLaunch, RunningPrograms {
    func find(_ name: String) -> String? {
        PathBinaryLocator().locate(name)
    }

    // `CreateProcess` runs a `.cmd` or `.bat` through cmd itself, with its
    // path quoted, so spaces, `(x86)` and `&` in it are kept.
    func command(_ path: String) -> [String] {
        [path]
    }

    // `-Command` loads the person's PowerShell profile, the closest Windows
    // has to a login shell's rc files.
    func command(printing variable: String, between begin: String, and end: String) -> [String] {
        ["powershell.exe", "-NoLogo", "-NonInteractive", "-Command", "'\(begin)' + $env:\(variable) + '\(end)'"]
    }

    func environment(for path: String, _ change: ProcessEnvironment) -> [String: String] {
        Self.environment(change)
    }

    // `terminate()` is `TerminateProcess`: the child ends at once.
    func end(_ child: Process) {
        if child.isRunning { child.terminate() }
    }

    /// The executable paths of the processes running now. A process this user
    /// can't open (a service, the system) is left out.
    func paths() -> [String] {
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

    /// The app's environment with the call's changes. Windows' variable names
    /// ignore case, so a change replaces or removes a name however it is spelled.
    static func environment(_ change: ProcessEnvironment,
                            base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        let removed = Set(change.unset.map { $0.uppercased() }).union(change.set.keys.map { $0.uppercased() })
        var environment = base.filter { !removed.contains($0.key.uppercased()) }
        environment.merge(change.set) { _, value in value }
        return environment
    }
}
#endif
