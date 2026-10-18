import Foundation
import Testing
@testable import DataSources

/// What a test needs from the platform (MODULAR_DESIGN §10). It runs wherever
/// `Platform.current` has that connection and is skipped elsewhere, saying
/// why, so the phase that brings a connection starts its tests with no edit.
extension Trait where Self == ConditionTrait {
    /// Reads a CLI's screen as a person sees it.
    static var needsTerminal: Self {
        .enabled(if: Platform.current.screenRenderer != nil,
                 "reads a CLI's screen: \(Platform.current.name) has no terminal yet (phase 5)")
    }

    /// Traverses the app's local server and its fallback chain.
    static var needsLocalServer: Self {
        let platform = Platform.current
        return .enabled(if: platform.localServer != nil && platform.processes != nil && platform.localNetwork != nil,
                        "reads a local server: \(platform.name) has no local-server connection yet (phase 5)")
    }

    /// Runs a `sh` script, as the example extension's are. Windows runs an
    /// extension's script as the file itself, and has no `sh` to run one.
    static var needsPOSIXShell: Self {
        .enabled(if: FileManager.default.isExecutableFile(atPath: "/bin/sh"),
                 "runs a sh script: \(Platform.current.name) has no /bin/sh")
    }
}
