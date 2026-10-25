import Foundation
import Testing
@testable import DataSources

/// This platform's terminal and program finder, the adapters the platform's
/// factory wires, for the suites over the neutral session — as
/// `ProcessesContract` reads `Platform.current` for the same reason.
enum PlatformTerminal {
    static let terminal: any PseudoTerminal = {
        #if canImport(Darwin)
        return MacPty()
        #elseif os(Windows)
        return ConPty()
        #else
        return LinuxPty()
        #endif
    }()

    static let programs: any InstalledPrograms & ChildLaunch = {
        #if canImport(Darwin)
        return MacProcesses()
        #elseif os(Windows)
        return WindowsProcesses()
        #else
        return LinuxProcesses()
        #endif
    }()

    /// This platform's program finder, for an app whose own environment is
    /// `environment`. A test hands one in rather than change the process':
    /// `setenv` while other tests read the environment can crash them.
    static func programs(appEnvironment environment: [String: String]) -> any InstalledPrograms & ChildLaunch {
        #if canImport(Darwin)
        return MacProcesses(appEnvironment: { environment })
        #elseif os(Windows)
        return WindowsProcesses(appEnvironment: { environment })
        #else
        return LinuxProcesses(appEnvironment: { environment })
        #endif
    }

    /// The screen a person would see for `output`, as a fetch renders it.
    static func screen(_ output: String) -> String {
        TerminalRenderer().render(output)
    }
}

/// A program a test runs in the terminal, written for each platform's shell:
/// `sh` on POSIX, PowerShell on Windows.
struct ShellProgram {
    let binary: String
    let arguments: [String]

    init(sh: String, powershell: String) {
        #if os(Windows)
        let root = ProcessInfo.processInfo.environment["SystemRoot"] ?? "C:\\Windows"
        binary = root + "\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"
        arguments = ["-NoLogo", "-NoProfile", "-NonInteractive", "-Command", powershell]
        #else
        binary = "/bin/sh"
        arguments = ["-c", sh]
        #endif
    }
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
