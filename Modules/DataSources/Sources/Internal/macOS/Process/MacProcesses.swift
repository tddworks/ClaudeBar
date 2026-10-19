#if os(macOS)
import Foundation
import Subprocess

/// What the Mac answers about programs: a CLI found through the login shell's
/// `PATH`, a script started by `sh`, a variable read from the person's login
/// shell, a child given the tool folders and ended with `SIGTERM` then
/// `SIGKILL`, and the kernel's process table.
struct MacProcesses: InstalledPrograms, ScriptStart, LoginShell, ChildLaunch, RunningPrograms {
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

    /// The app's environment with a PATH that finds tools outside a login
    /// shell — an app started by launchd gets a minimal one, which breaks a
    /// script whose shebang is `/usr/bin/env node` — then the call's changes.
    func environment(for path: String, _ change: ProcessEnvironment) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        var entries = (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":").map(String.init)
        var seen = Set(entries)
        let ownDirectory = URL(fileURLWithPath: path).deletingLastPathComponent().path
        for directory in [ownDirectory] + BinaryLocator.commonPaths where seen.insert(directory).inserted {
            entries.append(directory)
        }
        environment["PATH"] = entries.joined(separator: ":")
        for name in change.unset { environment.removeValue(forKey: name) }
        environment.merge(change.set) { _, value in value }
        return environment
    }

    // Asked to stop (`SIGTERM`), then killed after two seconds (#550).
    var teardown: [TeardownStep] {
        [.gracefulShutDown(allowedDurationToNextStep: .seconds(2))]
    }

    func paths() -> [String] {
        RunningProcesses.system()
    }
}
#endif
