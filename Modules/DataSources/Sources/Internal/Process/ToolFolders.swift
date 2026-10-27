import Foundation

/// Where a child finds the tools it calls, and where a CLI is looked for, when
/// the app started outside a login shell: launchd and a service hand it a
/// minimal `PATH`, which misses `~/.local/bin` and breaks a script whose
/// shebang is `/usr/bin/env node` (#604). Each platform names its tool
/// folders and separator; the merge is the same everywhere.
enum ToolFolders {
    /// `path`'s folders in order, without its empty entries, then each of
    /// `adding` it doesn't list yet, once.
    static func folders(_ path: String, adding: [String], separator: Character) -> [String] {
        var folders = path.split(separator: separator).map(String.init)
        var seen = Set(folders)
        for folder in adding where seen.insert(folder).inserted {
            folders.append(folder)
        }
        return folders
    }
}

/// A child's environment where variable names are exact, as on the Mac and
/// Linux (Windows' ignore case: `WindowsProcesses.environment`).
enum ChildEnvironment {
    /// `base` with a `PATH` that also lists the program's own folder and the
    /// tool folders (`defaultPath` when `base` has none), then `change`: its
    /// names removed, its defaults where `base` has no such name, its values
    /// over both.
    static func exactNames(_ base: [String: String], program path: String, defaultPath: String,
                           toolFolders: [String], change: ProcessEnvironment) -> [String: String] {
        var environment = base
        let programFolder = URL(fileURLWithPath: path).deletingLastPathComponent().path
        environment["PATH"] = ToolFolders.folders(environment["PATH"] ?? defaultPath,
                                                  adding: [programFolder] + toolFolders,
                                                  separator: ":").joined(separator: ":")
        for name in change.unset { environment.removeValue(forKey: name) }
        for (name, value) in change.defaults where environment[name] == nil { environment[name] = value }
        environment.merge(change.set) { _, value in value }
        return environment
    }
}
