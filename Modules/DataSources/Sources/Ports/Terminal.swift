import Foundation
import Mockable

// What an OS answers about a CLI's terminal session (MODULAR_DESIGN §10), one
// question each. The session above them — finding the CLI, typing, reading
// until the screen settles, rendering what it drew — is one neutral copy, as
// the programs' are.

/// A pseudo-terminal: the person's side and the program's, so a CLI believes
/// it is in a terminal and answers as it would there.
@Mockable
protocol PseudoTerminal: Sendable {
    /// Opens one of this size and answers its two ends: `session` to read and
    /// write, `child` for the program's standard files.
    func open(rows: UInt16, cols: UInt16) throws -> Ends

    /// The environment a CLI session here starts with: the app's, with a
    /// `PATH` that finds the person's tools and `change` applied — additions
    /// last, so they win.
    func environment(for path: String, _ change: ProcessEnvironment) -> [String: String]
}

/// The two ends of an opened pseudo-terminal. It sits beside the protocol,
/// not in it: a type nested in a protocol and named in a witness' signature
/// crashes Linux' silgen ("Invalid conformance in type-checked AST").
struct Ends: Sendable {
    /// Read and written by the session.
    let session: Int32
    /// The program's standard input, output and error.
    let child: Int32
}

/// Why a pseudo-terminal could not be opened.
enum PseudoTerminalError: Error {
    case couldNotOpen
}
