import Foundation
import Mockable

/// What the OS owns about starting a program (MODULAR_DESIGN §10): finding a
/// CLI, running one over pipes, holding a conversation with one, the programs
/// running, and how the person's script and login variables are reached. The
/// pipe runner and the conversation are the same code on every platform
/// (`PipeCLIExecutor`, `PipeConversation`); an adapter hands them its facts.
@Mockable
protocol Processes: Sendable {
    /// A CLI's full path, found as the person's terminal finds it, or `nil`
    /// when it isn't installed. A path to a file that is there is taken as it is.
    func locate(_ cli: String) -> String?

    /// Runs a program over pipes, in the app's environment with `change` applied.
    func runner(_ change: ProcessEnvironment) -> any CLIExecutor

    /// Starts `executable` for a newline-delimited conversation on its input
    /// and output, in `environment` (the app's when `nil`) and `directory`.
    func converse(_ executable: String, _ arguments: [String], _ environment: [String: String]?,
                  _ directory: URL?) throws -> any RPCTransport

    /// The executable paths of the programs running now.
    func running() -> [String]

    /// The argv that runs the person's script file at `path`.
    func script(_ path: String) -> [String]

    /// The argv that prints `variable` as the person's login sets it, between
    /// `LoginShellEnvironment`'s markers. `variable` is a valid name
    /// (`LoginShellEnvironment.isValidName`).
    func loginVariable(_ variable: String) -> [String]
}
