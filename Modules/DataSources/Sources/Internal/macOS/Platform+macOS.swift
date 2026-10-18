#if os(macOS)
import Foundation

extension Platform {
    /// The Mac: every connection the engine has.
    static let current = Platform(
        name: "macOS",
        timeZone: SystemTimeZone(),
        runCLI: CLIFetcher.system,
        processes: Processes(MacProcesses()),
        keychain: KeychainReader.system,
        browserCookies: SystemBrowserCookies(),
        browserStorage: SystemBrowserStorage(),
        localNetwork: InsecureLocalhostNetworkClient(),
        screenRenderer: { TerminalRenderer(cols: 160, rows: 50).render($0) },
        applicationData: { home, _ in home.appendingPathComponent("Library/Application Support", isDirectory: true) },
        localServer: macLocalServer,
        localServerCommands: macLocalServerCommands
    )
}
#endif
