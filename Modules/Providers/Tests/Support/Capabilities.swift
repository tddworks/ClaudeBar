import Testing
@testable import DataSources

/// What a test needs from the platform (MODULAR_DESIGN §10). It runs wherever
/// `Platform.current` has that connection and is skipped elsewhere, saying
/// why, so the phase that brings a connection starts its tests with no edit.
extension Trait where Self == ConditionTrait {
    /// Runs a CLI, a command or a script, or reads a CLI's screen.
    static var needsProcesses: Self {
        .enabled(if: Platform.current.runCommand != nil,
                 "runs a process: \(Platform.current.name) runs none yet (phase 5)")
    }

    /// Traverses the app's local server and its fallback chain.
    static var needsLocalServer: Self {
        let platform = Platform.current
        return .enabled(if: platform.localServer != nil && platform.runCommand != nil &&
                            platform.localNetwork != nil && platform.processList != nil,
                        "reads a local server: \(platform.name) has no local-server connection yet (phase 5)")
    }
}
