#if os(Linux)
import Foundation
import Subprocess

/// What Linux answers about programs: a CLI found on `PATH`, a script started
/// by `sh`, a variable read through the person's login shell, a child given
/// the tool folders and ended with `SIGTERM` then `SIGKILL`, and the kernel's
/// process table.
struct LinuxProcesses: InstalledPrograms, ScriptStart, LoginShell, ChildLaunch, RunningPrograms {
    func find(_ name: String) -> String? {
        LinuxBinaryLocator().locate(name)
    }

    // A script is a path, not shell source; positional argv preserves spaces,
    // quotes and metacharacters in the resolved filename.
    func command(_ path: String) -> [String] {
        ["/bin/sh", "-c", "exec \"$1\"", "claudebar-script", path]
    }

    func command(printing variable: String, between begin: String, and end: String) -> [String] {
        let preferred = ProcessInfo.processInfo.environment["SHELL"] ?? ""
        // `/bin/bash` rather than the Mac's `/bin/zsh`: a container or a
        // service often has no `SHELL` set, and bash is the login shell there.
        let binary = preferred.isEmpty ? "/bin/bash" : preferred
        // An interactive login shell sources both rc and profile files.
        return [binary, "-l", "-i", "-c", "printf '\(begin)%s\(end)\\n' \"$\(variable)\""]
    }

    /// The app's environment with a PATH that finds tools outside a login
    /// shell — an app started by a service gets a minimal one, which breaks a
    /// script whose shebang is `/usr/bin/env node` — then the call's changes.
    func environment(for path: String, _ change: ProcessEnvironment) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        var entries = (environment["PATH"] ?? "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin")
            .split(separator: ":").map(String.init)
        var seen = Set(entries)
        let ownDirectory = URL(fileURLWithPath: path).deletingLastPathComponent().path
        for directory in [ownDirectory] + Self.commonPaths where seen.insert(directory).inserted {
            entries.append(directory)
        }
        environment["PATH"] = entries.joined(separator: ":")
        for name in change.unset { environment.removeValue(forKey: name) }
        environment.merge(change.set) { _, value in value }
        return environment
    }

    // Asked to stop (`SIGTERM`), then killed after two seconds.
    var teardown: [TeardownStep] {
        [.gracefulShutDown(allowedDurationToNextStep: .seconds(2))]
    }

    func paths() -> [String] {
        RunningProcesses.system()
    }

    /// Where CLI tools are installed outside a login shell's `PATH`: the same
    /// folders the Mac's locator falls back to, in Linux' spellings.
    static var commonPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            // User-local installations
            "\(home)/.local/bin",
            "\(home)/.cargo/bin",
            "\(home)/.bun/bin",
            "\(home)/bin",
            // System-wide
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/local/sbin",
            "/usr/sbin",
            "/sbin",
            "/snap/bin",
            "/var/lib/flatpak/exports/bin",
            // Nix
            "\(home)/.nix-profile/bin",
            "/run/current-system/sw/bin",
            "/nix/var/nix/profiles/default/bin",
            // npm global (common locations)
            "\(home)/.npm-global/bin",
            // nvm (for node-based CLIs like codex)
            "\(home)/.nvm/versions",
        ]
    }
}

/// The executable paths of the processes running now, read from `/proc`
/// without starting a process. A process this user can't open — a service,
/// another person's — is left out.
enum RunningProcesses {
    static let system: @Sendable () -> [String] = {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: "/proc") else { return [] }
        var paths: [String] = []
        for entry in entries where entry.allSatisfy(\.isNumber) {
            if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: "/proc/\(entry)/exe") {
                paths.append(target)
            }
        }
        return paths
    }
}
#endif
