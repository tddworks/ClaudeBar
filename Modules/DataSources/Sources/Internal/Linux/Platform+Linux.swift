#if os(Linux)
import Foundation

extension Platform {
    /// Linux: paths, CLI discovery, programs over pipes and a CLI's terminal
    /// screen are available; the rest stays absent until its phase 5 slice and
    /// fails at its named step.
    static let current: Platform = {
        let linux = LinuxProcesses()
        return Platform(
            name: "Linux",
            timeZone: LinuxTimeZone(),
            runCLI: CLIFetcher.system(installed: linux, terminal: LinuxPty()),
            processes: Processes(linux),
            screenRenderer: { TerminalRenderer(cols: 160, rows: 50).render($0) },
            applicationData: { home, environment in
                // The spec answers absolute paths only; a relative value is
                // invalid and is ignored, the home's local share stepping in.
                if let data = environment("XDG_DATA_HOME"), data.hasPrefix("/") {
                    return URL(fileURLWithPath: data, isDirectory: true)
                }
                return home.appendingPathComponent(".local/share", isDirectory: true)
            }
        )
    }()
}
#endif
