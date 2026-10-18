import Foundation

extension DataSources {
    /// A login-shell fallback only when this platform offers that connection.
    /// Supplying an executor changes how it runs, never whether a shell exists.
    public static func makeLoginShellEnvironment(
        cliExecutor: (any CLIExecutor)? = nil,
        timeout: TimeInterval = 10
    ) -> LoginShellEnvironment? {
        makeLoginShellEnvironment(platform: .current, cliExecutor: cliExecutor, timeout: timeout)
    }

    static func makeLoginShellEnvironment(
        platform: Platform,
        cliExecutor: (any CLIExecutor)? = nil,
        timeout: TimeInterval = 10
    ) -> LoginShellEnvironment? {
        platform.processes?.loginEnvironment(runner: cliExecutor, timeout: timeout)
    }

    static func scriptCommands(for call: ScriptCall, platform: Platform = .current) -> [[String]] {
        platform.processes.map { [$0.scripts.command(call.run)] } ?? []
    }

    static func localServerCommands(for call: LocalServerCall, platform: Platform = .current) -> [[String]] {
        guard platform.localServer != nil, platform.processes != nil, platform.localNetwork != nil,
              let commands = platform.localServerCommands else { return [] }
        return commands(call.process)
    }

    /// Keep the app-owned folder's name: CLIs have already trusted it.
    static func cliWorkingDirectory() -> URL {
        cliWorkingDirectory(platform: .current, homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
                            environment: { ProcessInfo.processInfo.environment[$0] })
    }

    static func cliWorkingDirectory(
        platform: Platform,
        homeDirectory: URL,
        environment: @escaping @Sendable (String) -> String?
    ) -> URL {
        let path = expandPath("{{platform.appData}}/ClaudeBar/Probe", platform: platform,
                              homeDirectory: homeDirectory, environment: environment)
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

}
