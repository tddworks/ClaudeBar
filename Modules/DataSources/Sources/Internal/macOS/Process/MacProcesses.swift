#if os(macOS)
import Foundation

/// What the Mac answers about programs: a CLI found through the login shell's
/// `PATH`, a script started by `sh`, a variable read from the person's login
/// shell, and a child given the tool folders and ended with `SIGTERM` then
/// `SIGKILL`.
struct MacProcesses: InstalledPrograms, ScriptStart, LoginShell, ChildLaunch {
    /// The app's own environment, which a child's starts from.
    var appEnvironment: @Sendable () -> [String: String] = { ProcessInfo.processInfo.environment }

    func find(_ name: String) -> String? {
        BinaryLocator.which(name)
    }

    // A script is a path, not shell source; positional argv preserves spaces,
    // quotes and metacharacters in the resolved filename.
    func command(_ path: String) -> [String] {
        ["/bin/sh", "-c", "exec \"$1\"", "claudebar-script", path]
    }

    func command(printing variable: String, between begin: String, and end: String) -> [String] {
        let preferred = ProcessInfo.processInfo.environment["SHELL"] ?? ""
        let binary = preferred.isEmpty ? "/bin/zsh" : preferred
        // An interactive login shell sources both rc and profile files.
        return [binary, "-l", "-i", "-c", "printf '\(begin)%s\(end)\\n' \"$\(variable)\""]
    }

    /// The app's environment with the tool folders on `PATH` (launchd gives
    /// an app a minimal one), then the call's changes.
    func environment(for path: String, _ change: ProcessEnvironment) -> [String: String] {
        ChildEnvironment.exactNames(appEnvironment(), program: path, defaultPath: "/usr/bin:/bin:/usr/sbin:/sbin",
                                    toolFolders: BinaryLocator.commonPaths, change: change)
    }

    // Asked to stop (`SIGTERM`), then killed after two seconds (#550).
    var stopGrace: Duration? { .seconds(2) }
}
#endif
