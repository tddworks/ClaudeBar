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
    /// Finds and starts programs: `command`, `script`, `jsonRpc`, a `command`
    /// log, a login-shell lookup and the programs a `localServer` looks for.
    var processes: Processes?
    /// Reads a `keychain` item.
    var keychain: KeychainReader.Security?
    var browserCookies: (any BrowserCookieReading)?
    var browserStorage: (any BrowserStorageReading)?
    /// Talks to a server on this machine, for `localServer`.
    var localNetwork: (any NetworkClient)?
    /// Draws a terminal's raw output as the screen a person sees, for a
    /// `cli` fetch whose screen is `rendered`.
    var screenRenderer: (@Sendable (String) -> String)?
    /// The app-data folder for paths, using the caller's home and environment.
    var applicationData: (@Sendable (URL, @Sendable (String) -> String?) -> URL)?
    /// The separator accepted in this platform's filesystem paths.
    var pathSeparator: String
    var localServer: LocalServerFactory?
    var localServerCommands: LocalServerCommands?

    init(
        name: String,
        timeZone: any TimeZoneSource,
        runCLI: CLIFetcher.MakeExecutor? = nil,
        processes: Processes? = nil,
        keychain: KeychainReader.Security? = nil,
        browserCookies: (any BrowserCookieReading)? = nil,
        browserStorage: (any BrowserStorageReading)? = nil,
        localNetwork: (any NetworkClient)? = nil,
        screenRenderer: (@Sendable (String) -> String)? = nil,
        applicationData: (@Sendable (URL, @Sendable (String) -> String?) -> URL)? = nil,
        pathSeparator: String = "/",
        localServer: LocalServerFactory? = nil,
        localServerCommands: LocalServerCommands? = nil
    ) {
        self.name = name
        self.timeZone = timeZone
        self.runCLI = runCLI
        self.processes = processes
        self.keychain = keychain
        self.browserCookies = browserCookies
        self.browserStorage = browserStorage
        self.localNetwork = localNetwork
        self.screenRenderer = screenRenderer
        self.applicationData = applicationData
        self.pathSeparator = pathSeparator
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
