import Foundation

/// The dedicated directory every CLI fetch runs in.
///
/// Providers that gate on folder trust (Claude #44, Codex #267) prompt before
/// doing anything interactive. A CLI that inherits the app's cwd — usually
/// `/` when launched from Finder or at login — stalls on that prompt, so the
/// fetches run in this app-owned directory instead, where trust only needs to
/// be granted once and never blocks a refresh.
public enum CLIWorkingDirectory {
    /// Returns `Application Support/ClaudeBar/Probe`, creating it if needed.
    /// The folder keeps its old name: CLIs have already trusted it.
    public static func resolve() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        let dir = base
            .appendingPathComponent("ClaudeBar", isDirectory: true)
            .appendingPathComponent("Probe", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
