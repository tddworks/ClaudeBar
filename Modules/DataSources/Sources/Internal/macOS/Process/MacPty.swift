#if os(macOS)
import Darwin
import Foundation

/// The Mac's pty: `openpty` of the asked size, and a session environment whose
/// `PATH` is the person's login shell's, so a CLI is found where their
/// terminal finds it.
struct MacPty: PseudoTerminal {
    func open(rows: UInt16, cols: UInt16) throws -> Ends {
        var session: Int32 = -1
        var child: Int32 = -1
        var size = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&session, &child, nil, nil, &size) == 0 else {
            throw PseudoTerminalError.couldNotOpen
        }
        return Ends(session: session, child: child)
    }

    func environment(for path: String, _ change: ProcessEnvironment) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        // Remove excluded keys before setting defaults
        for key in change.unset {
            environment.removeValue(forKey: key)
        }
        environment["PATH"] = Self.withCommonPaths(BinaryLocator.shellPath())
        environment["HOME"] = environment["HOME"] ?? NSHomeDirectory()
        environment["TERM"] = environment["TERM"] ?? "xterm-256color"
        environment["COLORTERM"] = environment["COLORTERM"] ?? "truecolor"
        environment["LANG"] = environment["LANG"] ?? "en_US.UTF-8"
        environment["CI"] = environment["CI"] ?? "0"
        for (key, value) in change.set {
            environment[key] = value
        }
        return environment
    }

    /// Ensures common tool paths are included in `PATH`.
    ///
    /// When apps are launched from Finder/launchd, the PATH obtained from login shell
    /// may not include paths configured in .zshrc/.bashrc (which are only loaded for
    /// interactive shells). This ensures common installation paths are always available.
    private static func withCommonPaths(_ path: String) -> String {
        let essentialPaths = [
            "/opt/homebrew/bin",  // Homebrew on Apple Silicon
            "/opt/homebrew/sbin",
            "/usr/local/bin",     // Homebrew on Intel / common tools
            "/usr/local/sbin",
        ]

        var components = path.split(separator: ":").map(String.init)
        let fm = FileManager.default

        for essentialPath in essentialPaths.reversed() {
            if !components.contains(essentialPath) && fm.fileExists(atPath: essentialPath) {
                components.insert(essentialPath, at: 0)
            }
        }

        return components.joined(separator: ":")
    }
}
#endif
