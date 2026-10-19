import Foundation
import Mockable
import Subprocess
@testable import DataSources

extension Processes {
    /// Programs each run on what `runner` answers for its environment, found
    /// as that runner finds them, a conversation that answers nothing, none
    /// running, and a script started as the file itself, whatever the OS.
    static func running(_ runner: @escaping Processes.Pipes) -> Processes {
        Processes(FixtureOS()).with(pipes: runner, conversation: { _, _, _, _ in MockRPCTransport() }, paths: { [] })
    }
}

/// An OS that answers every fact plainly, for a test that hands its runner in.
private struct FixtureOS: InstalledPrograms, ScriptStart, LoginShell, ChildLaunch, RunningPrograms {
    func find(_ name: String) -> String? { nil }
    func command(_ path: String) -> [String] { [path] }
    func command(printing variable: String, between begin: String, and end: String) -> [String] { ["fixture-shell", variable] }
    func environment(for path: String, _ change: ProcessEnvironment) -> [String: String] { change.set }
    var teardown: [TeardownStep] { [] }
    func paths() -> [String] { [] }
}
