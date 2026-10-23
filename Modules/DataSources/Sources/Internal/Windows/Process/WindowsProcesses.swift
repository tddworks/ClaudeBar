#if os(Windows)
import Foundation

/// What Windows answers about programs: a CLI found on `PATH` with
/// `PATHEXT`, a script run as the file itself, a variable read through the
/// person's PowerShell profile, and a child in the app's environment ended
/// with `TerminateProcess`.
struct WindowsProcesses: InstalledPrograms, ScriptStart, LoginShell, ChildLaunch {
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

    // No step before the last kill, `TerminateProcess`: the child ends at
    // once. Windows' graceful step attaches to the child's console, which a
    // GUI app shouldn't do.
    var stopGrace: Duration? { nil }

    /// The app's environment with the call's changes. Windows' variable names
    /// ignore case, so a change replaces or removes a name however it is
    /// spelled, and a default is set only where no spelling of it is left.
    static func environment(_ change: ProcessEnvironment,
                            base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        let removed = Set(change.unset.map { $0.uppercased() }).union(change.set.keys.map { $0.uppercased() })
        var environment = base.filter { !removed.contains($0.key.uppercased()) }
        // A name `set` also gives is left to it, so no two spellings remain.
        let present = Set(environment.keys.map { $0.uppercased() }).union(change.set.keys.map { $0.uppercased() })
        for (name, value) in change.defaults where !present.contains(name.uppercased()) { environment[name] = value }
        environment.merge(change.set) { _, value in value }
        return environment
    }
}
#endif
