import Foundation
import Mockable
import Subprocess

// What an OS answers about programs (MODULAR_DESIGN §10), one question each.
// A platform's adapter answers all four; `Processes` and `Program` above them
// find, run, talk and report the same way on every platform.

/// Finds a program the person installed, as their terminal finds it.
@Mockable
protocol InstalledPrograms: Sendable {
    /// The program's full path, or `nil` when it isn't installed. A path to a
    /// file that is there is taken as it is.
    func find(_ name: String) -> String?
}

/// How this OS starts the person's script file.
@Mockable
protocol ScriptStart: Sendable {
    /// The argv that runs the script at `path`, before its arguments.
    func command(_ path: String) -> [String]
}

/// How this OS reads a variable as the person's login sets it.
@Mockable
protocol LoginShell: Sendable {
    /// The argv that prints `variable`'s value between `begin` and `end`.
    /// `variable` is a valid name (`LoginShellEnvironment.isValidName`).
    func command(printing variable: String, between begin: String, and end: String) -> [String]
}

/// How this OS launches a child and ends one.
@Mockable
protocol ChildLaunch: Sendable {
    /// The environment the program at `path` starts with: the app's, with
    /// `change` applied under this OS's name rule.
    func environment(for path: String, _ change: ProcessEnvironment) -> [String: String]

    /// How long a child is given to stop once asked, before a last kill;
    /// `nil` where the OS has no step a GUI app should take first, and the
    /// child is killed at once. A conversation's end and a terminal
    /// session's end both read it.
    var stopGrace: Duration? { get }
}

extension ChildLaunch {
    /// `stopGrace` as Subprocess' teardown sequence, for a conversation's end.
    var teardown: [TeardownStep] {
        stopGrace.map { [.gracefulShutDown(allowedDurationToNextStep: $0)] } ?? []
    }
}
