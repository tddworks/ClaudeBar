#if os(Windows)
import Foundation

extension Platform {
    /// File paths, CLI discovery, programs over pipes and in a pseudo
    /// console, and an app's own server are available; the rest stays absent
    /// until its phase 5 slice and fails at its named step.
    static let current = Platform(
        name: "Windows",
        timeZone: WindowsTimeZone(),
        runCLI: CLIFetcher.system(installed: WindowsProcesses(), terminal: ConPty()),
        processes: Processes(WindowsProcesses()),
        localServers: LocalServers(WindowsLocalServers()),
        screenRenderer: { TerminalRenderer(cols: 160, rows: 50).render($0) },
        applicationData: { home, environment in
            if let path = environment("APPDATA"), !path.isEmpty {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            return home.appendingPathComponent("AppData/Roaming", isDirectory: true)
        },
        pathSeparator: "\\"
    )
}
#endif
