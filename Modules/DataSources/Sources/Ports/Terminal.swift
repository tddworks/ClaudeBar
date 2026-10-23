import Foundation
import Mockable

// What an OS answers about a CLI's terminal session (MODULAR_DESIGN §10), one
// question each. The session above them — finding the CLI, typing, reading
// until the screen settles, rendering what it drew — is one neutral copy, as
// the programs' are.

/// A pseudo-terminal: the person's side and the program's, so a CLI believes
/// it is in a terminal and answers as it would there. Starting the program is
/// the OS's step too: a POSIX pty becomes the child's standard files, while a
/// Windows pseudo console is attached to the child as it is created.
@Mockable
protocol PseudoTerminal: Sendable {
    /// Opens a pseudo-terminal of the launch's size and starts its program in
    /// it. Throws `PseudoTerminalError` when either step fails.
    func start(_ launch: TerminalLaunch) throws -> any TerminalSession

    /// The `PATH` a session starts with, where this OS's terminal differs
    /// from a program's over pipes (`ChildLaunch`): the Mac's login shell's.
    /// `nil` keeps the program's.
    func sessionPath() -> String?

    /// The locale (`LANG`) a session falls back to when the app has none;
    /// `nil` where the OS reads no such variable.
    var fallbackLocale: String? { get }
}

/// What to start in a pseudo-terminal, and its size. It sits beside the
/// protocol, not in it: a type nested in a protocol and named in a witness'
/// signature crashes Linux' silgen ("Invalid conformance in type-checked AST").
struct TerminalLaunch: Sendable {
    let executable: String
    let arguments: [String]
    let environment: [String: String]
    /// The folder the program starts in; the app's own when `nil`.
    let directory: URL?
    let rows: UInt16
    let cols: UInt16
    /// The fetch's quality of service, where the OS has one for a process
    /// tree (#204).
    let qualityOfService: QualityOfService
    /// How long the program is given to stop once asked, at the session's
    /// end: its OS's `ChildLaunch.stopGrace`.
    let stopGrace: Duration?
}

/// One program running in a pseudo-terminal: what it has drawn, what is typed
/// into it, and its end.
protocol TerminalSession: AnyObject, Sendable {
    /// What the program drew since the last read; empty when nothing arrived.
    /// Never waits.
    func read() -> Data

    /// Types `data` into the terminal.
    func write(_ data: Data) throws

    /// Whether the session may still draw: the program is running, or what
    /// it drew before it ended is still on its way.
    var isRunning: Bool { get }

    /// The program's exit code once it has ended; `nil` while it runs.
    var exitCode: Int32? { get }

    /// Ends the program, within a bound, and closes the terminal. Safe to call
    /// more than once.
    func end()
}

/// Why a pseudo-terminal could not run a program.
enum PseudoTerminalError: Error {
    /// The pseudo-terminal itself could not be opened.
    case couldNotOpen
    /// It opened, but the program did not start; the reason names the step.
    case couldNotStart(String)
}
