#if os(macOS)
import Foundation

extension Platform {
    /// The Mac: every connection the engine has.
    static let current = Platform(
        name: "macOS",
        timeZone: SystemTimeZone(),
        runCLI: CLIFetcher.system,
        runCommand: CommandFetcher.system,
        rpcTransport: { executable, arguments, environment, directory in
            try ProcessRPCTransport(executable: executable, arguments: arguments, environment: environment,
                                    workingDirectory: directory)
        },
        keychain: KeychainReader.system,
        browserCookies: SystemBrowserCookies(),
        browserStorage: SystemBrowserStorage(),
        localNetwork: InsecureLocalhostNetworkClient(),
        processList: RunningProcesses.system,
        screenRenderer: { TerminalRenderer(cols: 160, rows: 50).render($0) },
        binaryLocator: BinaryLocator(),
        applicationData: { home, _ in home.appendingPathComponent("Library/Application Support", isDirectory: true) },
        scriptCommand: macScriptCommand,
        loginShellCommand: macLoginShellCommand,
        localServer: macLocalServer,
        localServerCommands: macLocalServerCommands
    )
}
#endif
