#if canImport(Darwin) || canImport(Glibc)
import Testing
@testable import DataSources

/// This platform's terminal and program finder, the adapters the platform's
/// factory wires, for the suites over the neutral session — as
/// `ProcessesContract` reads `Platform.current` for the same reason.
enum PlatformTerminal {
    static let terminal: any PseudoTerminal = {
        #if canImport(Darwin)
        return MacPty()
        #else
        return LinuxPty()
        #endif
    }()

    static let installed: any InstalledPrograms = {
        #if canImport(Darwin)
        return MacProcesses()
        #else
        return LinuxProcesses()
        #endif
    }()
}

extension Trait where Self == ConditionTrait {
    /// Reads a CLI's screen on this platform's terminal, wherever the platform
    /// has one, and is skipped elsewhere, saying why, so the phase that brings
    /// a terminal starts its tests with no edit.
    static var needsTerminal: Self {
        .enabled(if: Platform.current.runCLI != nil && Platform.current.screenRenderer != nil,
                 "reads a CLI's screen: \(Platform.current.name) has no terminal yet (phase 5)")
    }
}
#endif
