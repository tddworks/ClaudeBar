#if os(Linux)
import Foundation

/// What Linux answers about programs: a CLI found on `PATH`, a script started
/// by `sh`, a variable read through the person's login shell, a child given
/// the tool folders and ended with `SIGTERM` then `SIGKILL`.
struct LinuxProcesses: InstalledPrograms, ScriptStart, LoginShell, ChildLaunch {
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
        for (name, value) in change.defaults where environment[name] == nil { environment[name] = value }
        environment.merge(change.set) { _, value in value }
        return environment
    }

    // Asked to stop (`SIGTERM`), then killed after two seconds.
    var stopGrace: Duration? { .seconds(2) }

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
#endif
