#if os(Windows)
import Foundation

extension Platform {
    /// File paths, CLI discovery, programs over pipes and in a pseudo
    /// console, an app's own server and Credential Manager are available;
    /// browser cookies and storage stay absent and fail at their named step.
    static let current = Platform(
        name: "Windows",
        timeZone: WindowsTimeZone(),
        runCLI: CLIFetcher.system(programs: WindowsProcesses(), terminal: ConPty()),
        processes: Processes(WindowsProcesses()),
        keychain: CredentialManagerKeychain(),
        localServers: LocalServers(WindowsLocalServers()),
        screenRenderer: { TerminalRenderer().render($0) },
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
