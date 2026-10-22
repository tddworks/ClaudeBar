#if os(Linux)
import Foundation

extension Platform {
    /// Linux: paths, CLI discovery and programs over pipes are available; the
    /// rest stays absent until its phase 5 slice and fails at its named step.
    static let current = Platform(
        name: "Linux",
        timeZone: LinuxTimeZone(),
        processes: Processes(LinuxProcesses()),
        applicationData: { home, environment in
            // The XDG spec: a relative path is invalid and is ignored.
            if let data = environment("XDG_DATA_HOME"), data.hasPrefix("/") {
                return URL(fileURLWithPath: data, isDirectory: true)
            }
            return home.appendingPathComponent(".local/share", isDirectory: true)
        }
    )
}
#endif
