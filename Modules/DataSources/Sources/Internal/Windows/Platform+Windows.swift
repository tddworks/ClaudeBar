#if os(Windows)
import Foundation

extension Platform {
    /// File paths, CLI discovery and programs over pipes are available; the
    /// rest stays absent until its phase 5 slice and fails at its named step.
    static let current = Platform(
        name: "Windows",
        timeZone: WindowsTimeZone(),
        processes: Processes(WindowsProcesses()),
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
