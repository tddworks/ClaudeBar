#if os(macOS)
import Foundation

extension Platform {
    /// The Mac: every connection the engine has.
    static let current: Platform = {
        let mac = MacProcesses()
        return Platform(
            name: "macOS",
            timeZone: SystemTimeZone(),
            runCLI: CLIFetcher.system(programs: mac, terminal: MacPty()),
            processes: Processes(mac),
            keychain: SecurityKeychain(),
            browserCookies: SystemBrowserCookies(),
            browserStorage: SystemBrowserStorage(),
            safeStorage: SafeStorage(KeychainSafeStorageKeys()),
            localServers: LocalServers(MacLocalServers()),
            screenRenderer: { TerminalRenderer().render($0) },
            applicationData: { home, _ in home.appendingPathComponent("Library/Application Support", isDirectory: true) }
        )
    }()
}
#endif
