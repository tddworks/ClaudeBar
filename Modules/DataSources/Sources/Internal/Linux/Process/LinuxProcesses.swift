#if os(Linux)
import Foundation

/// What Linux answers about programs: a CLI found on `PATH`, a script started
/// by `sh`, a variable read through the person's login shell, a child given
/// the tool folders and ended with `SIGTERM` then `SIGKILL`.
struct LinuxProcesses: InstalledPrograms, ScriptStart, LoginShell, ChildLaunch {
    /// The app's own environment, which a child's starts from.
    var appEnvironment: @Sendable () -> [String: String] = { ProcessInfo.processInfo.environment }

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

    /// The app's environment with the tool folders on `PATH` (a service gives
    /// an app a minimal one), then the call's changes.
    func environment(for path: String, _ change: ProcessEnvironment) -> [String: String] {
        ChildEnvironment.exactNames(appEnvironment(), program: path,
                                    defaultPath: "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                                    toolFolders: Self.commonPaths, change: change)
    }

    // Asked to stop (`SIGTERM`), then killed after two seconds.
    var stopGrace: Duration? { .seconds(2) }

    /// Where CLI tools are installed outside a login shell's `PATH`: the same
    /// folders the Mac's locator falls back to, in Linux' spellings. A child's
    /// `PATH` lists them, and the locator looks in them after `PATH`'s.
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
