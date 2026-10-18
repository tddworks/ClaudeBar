/// A platform's worker for discovering and querying an app's local server.
typealias LocalServerFactory = @Sendable (
    _ call: LocalServerCall,
    _ commands: any CLIExecutor,
    _ network: any NetworkClient,
    _ processPaths: @escaping @Sendable () -> [String]
) -> any Fetching

/// The commands a local server connection may run, for Import's disclosure.
typealias LocalServerCommands = @Sendable (_ process: LocalServerCall.Process) -> [[String]]
