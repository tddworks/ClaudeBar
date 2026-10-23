import Diagnostics
import Foundation
import Quotas

/// A program the person has, an installed CLI or their own script, found and
/// started the way this OS starts it. It runs or talks when told, and reports
/// a failure as a fact a definition's `errors` may word: gone, couldn't start,
/// or exited non-zero.
struct Program: Sendable {
    /// What a failure names it by: the CLI's name or the script's file name.
    let name: String
    /// The argv that starts it, before its arguments.
    let command: [String]
    let processes: Processes

    /// Runs it to the end over pipes and answers with what it printed, stdout
    /// and stderr as one text.
    func run(_ arguments: [String] = [], input: String? = nil, environment: ProcessEnvironment = ProcessEnvironment(),
             timeout: TimeInterval, in directory: URL?) async throws -> String {
        let result: CLIResult
        do {
            result = try await processes.pipes(environment).execute(
                binary: command[0], args: Array(command.dropFirst()) + arguments, input: input, timeout: timeout,
                workingDirectory: directory, autoResponses: [:]
            )
        } catch UsageError.cliNotFound {
            // Gone between finding it and running it.
            throw CLIMissingError(cli: name)
        } catch let error as UsageError {
            throw error
        } catch {
            AppLog.probes.error("\(name) could not start")
            throw CLILaunchError(cli: name)
        }
        guard result.exitCode == 0 else {
            AppLog.probes.error("\(name) exited with \(result.exitCode)")
            throw CLIExitError(cli: name, exitCode: result.exitCode)
        }
        AppLog.probes.debug("\(name) answered (\(result.output.count) chars)")
        return result.output
    }

    /// Starts it for a newline-delimited conversation on its input and output.
    func talk(_ arguments: [String], environment: ProcessEnvironment = ProcessEnvironment(),
              in directory: URL?) throws -> any RPCTransport {
        try processes.conversation(command[0], Array(command.dropFirst()) + arguments,
                                   processes.launch.environment(for: command[0], environment), directory)
    }
}

/// The programs on this machine, as a data source reaches them: an installed
/// CLI or the person's script, found and ready to run, and what the person's
/// login sets (MODULAR_DESIGN §10). The OS answers four facts; finding,
/// running and talking are this one copy.
struct Processes: Sendable {
    /// How a program runs over pipes, for a change to its environment.
    typealias Pipes = @Sendable (ProcessEnvironment) -> any CLIExecutor

    let installed: any InstalledPrograms
    let scripts: any ScriptStart
    let loginShell: any LoginShell
    let launch: any ChildLaunch
    /// Runs a program over pipes: `PipeCLIExecutor`, unless a test hands its own.
    let pipes: Pipes
    /// Holds a conversation with a program: `PipeConversation`, unless a test
    /// hands its own.
    let conversation: DataSources.TransportFactory

    /// This OS's answers, its programs run on the one pipe runner and conversation.
    init(_ os: some InstalledPrograms & ScriptStart & LoginShell & ChildLaunch) {
        self.init(installed: os, scripts: os, loginShell: os, launch: os)
    }

    init(installed: any InstalledPrograms, scripts: any ScriptStart, loginShell: any LoginShell, launch: any ChildLaunch) {
        self.init(installed: installed, scripts: scripts, loginShell: loginShell, launch: launch,
                  pipes: { PipeCLIExecutor(change: $0, installed: installed, launch: launch) },
                  conversation: { path, arguments, environment, directory in
                      PipeConversation(executablePath: path, arguments: arguments,
                                       environment: environment ?? launch.environment(for: path, ProcessEnvironment()),
                                       directory: directory, teardown: launch.teardown)
                  })
    }

    private init(installed: any InstalledPrograms, scripts: any ScriptStart, loginShell: any LoginShell,
                 launch: any ChildLaunch, pipes: @escaping Pipes, conversation: @escaping DataSources.TransportFactory) {
        self.installed = installed
        self.scripts = scripts
        self.loginShell = loginShell
        self.launch = launch
        self.pipes = pipes
        self.conversation = conversation
    }

    /// This OS's facts, with programs run on `pipes`, found as `pipes` finds
    /// them, and talked to through `conversation`: what the factory's stubbed
    /// `make` and a test hand in.
    func with(pipes: @escaping Pipes, conversation: @escaping DataSources.TransportFactory) -> Processes {
        Processes(installed: FoundBy(pipes: pipes), scripts: scripts, loginShell: loginShell, launch: launch,
                  pipes: pipes, conversation: conversation)
    }

    /// The installed CLI `name`, or `nil` when it isn't installed.
    func program(named name: String) -> Program? {
        installed.find(name).map { Program(name: name, command: [$0], processes: self) }
    }

    /// The person's script at `path`, or `nil` when no file is there.
    func script(at path: String) -> Program? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return Program(name: URL(fileURLWithPath: path).lastPathComponent, command: scripts.command(path), processes: self)
    }

    /// A variable as the person's login sets it, read on `pipes` unless a
    /// runner is handed in.
    func loginEnvironment(runner: (any CLIExecutor)? = nil, timeout: TimeInterval = 10) -> LoginShellEnvironment {
        LoginShellEnvironment(cliExecutor: runner ?? pipes(ProcessEnvironment()), shell: loginShell, timeout: timeout)
    }
}

/// Programs found as a handed runner finds them.
private struct FoundBy: InstalledPrograms {
    let pipes: Processes.Pipes
    func find(_ name: String) -> String? { pipes(ProcessEnvironment()).locate(name) }
}
