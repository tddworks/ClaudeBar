#if os(Linux)
import Foundation

/// What Linux answers about programs: a CLI found on `PATH`, a script started
/// by `sh`, a variable read through the person's login shell, a child given
/// the tool folders and ended with `SIGTERM` then `SIGKILL`.
struct LinuxProcesses: InstalledPrograms, ScriptStart, LoginShell, ChildLaunch {
    /// The app's own environment, which a child's starts from.
    var appEnvironment: @Sendable () -> [String: String] = { ProcessInfo.processInfo.environment }
    /// The person's home folder, which most tool folders are under.
    var home: @Sendable () -> String = { FileManager.default.homeDirectoryForCurrentUser.path }

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
        let app = appEnvironment()
        return ChildEnvironment.exactNames(app, program: path,
                                           defaultPath: "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                                           toolFolders: Self.commonPaths(home: home(), environment: app),
                                           change: change)
    }

    // Asked to stop (`SIGTERM`), then killed after two seconds.
    var stopGrace: Duration? { .seconds(2) }

    /// Where CLI tools are installed outside a login shell's `PATH`: the same
    /// folders the Mac's locator falls back to, in Linux' spellings, and the
    /// version managers' (#682), which only shell setup puts on `PATH`. A
    /// child's `PATH` lists them, and the locator looks in them after `PATH`'s.
    static var commonPaths: [String] {
        commonPaths(home: FileManager.default.homeDirectoryForCurrentUser.path,
                    environment: ProcessInfo.processInfo.environment)
    }

    /// The tool folders of a person whose home is `home`; `environment` gives
    /// the XDG data and config folders, where fnm, mise and nvm can live.
    static func commonPaths(home: String, environment: [String: String]) -> [String] {
        let data = xdgFolders(environment["XDG_DATA_HOME"], default: "\(home)/.local/share")
        let config = xdgFolders(environment["XDG_CONFIG_HOME"], default: "\(home)/.config")
        let userLocal = [
            "\(home)/.local/bin",
            "\(home)/.cargo/bin",
            "\(home)/.bun/bin",
            "\(home)/bin",
        ]
        // Version managers: each nvm version's `bin`, Volta's, fnm's default
        // version's, and mise's and asdf's shims.
        let nvm: [String] = ["\(home)/.nvm"] + config.map { "\($0)/nvm" }
        var versionManagers: [String] = nvm.flatMap(nvmFolders)
        versionManagers.append("\(home)/.volta/bin")
        versionManagers += data.map { "\($0)/fnm/aliases/default/bin" }
        versionManagers += data.map { "\($0)/mise/shims" }
        versionManagers.append("\(home)/.asdf/shims")
        let elsewhere = [
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
        ]
        return userLocal + versionManagers + elsewhere
    }

    /// An XDG base folder: the variable's when it is an absolute path, then
    /// the default, since a service may lack the variable the shell sets.
    private static func xdgFolders(_ value: String?, default fallback: String) -> [String] {
        guard let value, value.hasPrefix("/"), value != fallback else { return [fallback] }
        return [value, fallback]
    }

    /// The `bin` of each Node version installed under nvm's folder `nvm`: the
    /// one nvm's `default` alias names first, then the rest newest first.
    private static func nvmFolders(_ nvm: String) -> [String] {
        let node = "\(nvm)/versions/node"
        let installed = ((try? FileManager.default.contentsOfDirectory(atPath: node)) ?? [])
            .compactMap { name in versionNumbers(name).map { (name: name, numbers: $0) } }
            .sorted { $1.numbers.lexicographicallyPrecedes($0.numbers) }
        var names = installed.map(\.name)
        if let preferred = nvmDefault(nvm, among: installed), let index = names.firstIndex(of: preferred) {
            names.insert(names.remove(at: index), at: 0)
        }
        return names.map { "\(node)/\($0)/bin" }
    }

    /// The installed version nvm's `default` alias names, newest first in
    /// `installed`: a whole or partial version (`v22.1.0`, `22`), `node` or
    /// `stable` for the newest, or another alias such as `lts/*`, whose file
    /// names the next. Nil when it names none installed, as `system` does.
    private static func nvmDefault(_ nvm: String, among installed: [(name: String, numbers: [Int])]) -> String? {
        var alias = "default"
        // An alias names another a few times at most; a loop ends here.
        for _ in 0..<8 {
            guard let text = try? String(contentsOfFile: "\(nvm)/alias/\(alias)", encoding: .utf8) else { break }
            alias = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if alias == "node" || alias == "stable" { return installed.first?.name }
        guard let wanted = versionNumbers(alias) else { return nil }
        return installed.first { $0.numbers.count >= wanted.count && Array($0.numbers.prefix(wanted.count)) == wanted }?.name
    }

    /// A version's numbers, `v22.1.0` or `22.1` as [22, 1, 0] or [22, 1]; nil
    /// for a name.
    private static func versionNumbers(_ version: String) -> [Int]? {
        let digits = version.hasPrefix("v") ? version.dropFirst() : Substring(version)
        let parts = digits.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { Int($0) }
        return !digits.isEmpty && numbers.count == parts.count ? numbers : nil
    }
}
#endif
