#if os(Windows)
import Foundation

extension Platform {
    /// File paths, CLI discovery, programs over pipes and in a pseudo
    /// console, an app's own server, Credential Manager and an Electron app's
    /// safeStorage are available; browser cookies and storage stay absent and
    /// fail at their named step.
    static let current = Platform(
        name: "Windows",
        timeZone: WindowsTimeZone(),
        runCLI: CLIFetcher.system(programs: WindowsProcesses(), terminal: ConPty()),
        processes: Processes(WindowsProcesses()),
        keychain: CredentialManagerKeychain(),
        safeStorage: SafeStorage(LocalStateSafeStorageKeys(applicationData: {
            windowsApplicationData(FileManager.default.homeDirectoryForCurrentUser) { ProcessInfo.processInfo.environment[$0] }
        })),
        localServers: LocalServers(WindowsLocalServers()),
        screenRenderer: { TerminalRenderer().render($0) },
        applicationData: windowsApplicationData,
        pathSeparator: "\\"
    )

    /// `%APPDATA%`, or the home's `AppData\Roaming` without it.
    private static let windowsApplicationData: @Sendable (URL, @Sendable (String) -> String?) -> URL = { home, environment in
        if let path = environment("APPDATA"), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return home.appendingPathComponent("AppData/Roaming", isDirectory: true)
    }
}
#endif
