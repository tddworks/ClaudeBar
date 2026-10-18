import Foundation

/// What this machine offers the module's workers (MODULAR_DESIGN §10, "One
/// place picks the platform"): a way to run a CLI, a Keychain, the person's
/// zone. A library is not here: QuickJS and SQLite are the same on every
/// platform (#570). Each platform folder defines `current` once, the only place a
/// platform is chosen; neutral code reads the value and never asks which OS
/// it runs on.
///
/// A `nil` connection means one thing: this platform has none. The factory
/// fails a case that needs it as `Unavailable`. Only the factory reads a
/// `Platform`, and it hands each worker the one thing that worker uses (§4).
struct Platform: Sendable {
    /// How a person names it: "macOS", "Windows".
    let name: String
    /// The person's time zone. Every platform has one, so it is never `nil`.
    var timeZone: any TimeZoneSource
    /// Runs a CLI for a `cli` fetch or a CLI renewal.
    var runCLI: CLIFetcher.MakeExecutor?
    /// Runs a command or script over pipes: `command`, `script`, `localServer`.
    var runCommand: CommandFetcher.MakeExecutor?
    /// Starts a CLI for a `jsonRpc` conversation.
    var rpcTransport: DataSources.TransportFactory?
    /// Reads a `keychain` item.
    var keychain: KeychainReader.Security?
    var browserCookies: (any BrowserCookieReading)?
    var browserStorage: (any BrowserStorageReading)?
    /// Talks to a server on this machine, for `localServer`.
    var localNetwork: (any NetworkClient)?
    /// The command lines of the processes running, for `localServer`.
    var processList: (@Sendable () -> [String])?
    /// Draws a terminal's raw output as the screen a person sees, for a
    /// `cli` fetch whose screen is `rendered`.
    var screenRenderer: (@Sendable (String) -> String)?
    var binaryLocator: (any BinaryLocating)?
    /// The app-data folder for paths, using the caller's home and environment.
    var applicationData: (@Sendable (URL, @Sendable (String) -> String?) -> URL)?
    /// The separator accepted in this platform's filesystem paths.
    var pathSeparator: String
    var scriptCommand: ScriptCommand?
    var loginShellCommand: LoginShellCommand?
    var localServer: LocalServerFactory?
    var localServerCommands: LocalServerCommands?

    init(
        name: String,
        timeZone: any TimeZoneSource,
        runCLI: CLIFetcher.MakeExecutor? = nil,
        runCommand: CommandFetcher.MakeExecutor? = nil,
        rpcTransport: DataSources.TransportFactory? = nil,
        keychain: KeychainReader.Security? = nil,
        browserCookies: (any BrowserCookieReading)? = nil,
        browserStorage: (any BrowserStorageReading)? = nil,
        localNetwork: (any NetworkClient)? = nil,
        processList: (@Sendable () -> [String])? = nil,
        screenRenderer: (@Sendable (String) -> String)? = nil,
        binaryLocator: (any BinaryLocating)? = nil,
        applicationData: (@Sendable (URL, @Sendable (String) -> String?) -> URL)? = nil,
        pathSeparator: String = "/",
        scriptCommand: ScriptCommand? = nil,
        loginShellCommand: LoginShellCommand? = nil,
        localServer: LocalServerFactory? = nil,
        localServerCommands: LocalServerCommands? = nil
    ) {
        self.name = name
        self.timeZone = timeZone
        self.runCLI = runCLI
        self.runCommand = runCommand
        self.rpcTransport = rpcTransport
        self.keychain = keychain
        self.browserCookies = browserCookies
        self.browserStorage = browserStorage
        self.localNetwork = localNetwork
        self.processList = processList
        self.screenRenderer = screenRenderer
        self.binaryLocator = binaryLocator
        self.applicationData = applicationData
        self.pathSeparator = pathSeparator
        self.scriptCommand = scriptCommand
        self.loginShellCommand = loginShellCommand
        self.localServer = localServer
        self.localServerCommands = localServerCommands
    }

    /// This platform's name and zone and no connection: what a test hands the
    /// factory to see, on any platform, what a platform without a connection does.
    static var bare: Platform { Platform(name: current.name, timeZone: current.timeZone) }

    /// The calendar a day is counted in: the system's, in the person's zone.
    var calendar: Calendar {
        var calendar = Calendar.current
        calendar.timeZone = timeZone.current()
        return calendar
    }
}
