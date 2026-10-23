import Foundation
import Testing
@testable import DataSources
#if os(Windows)
import WinSDK
#endif

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

    static let installed: any InstalledPrograms = {
        #if canImport(Darwin)
        return MacProcesses()
        #elseif os(Windows)
        return WindowsProcesses()
        #else
        return LinuxProcesses()
        #endif
    }()

    /// The screen a person would see for `output`, as a fetch renders it.
    static func screen(_ output: String) -> String {
        TerminalRenderer(cols: 160, rows: 50).render(output)
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

/// Sets `name` in this process' environment, or removes it when `value` is nil.
func setEnvironmentVariable(_ name: String, _ value: String?) {
    #if os(Windows)
    _ = name.withCString(encodedAs: UTF16.self) { key in
        guard let value else { return SetEnvironmentVariableW(key, nil) }
        return value.withCString(encodedAs: UTF16.self) { SetEnvironmentVariableW(key, $0) }
    }
    #else
    if let value { setenv(name, value, 1) } else { unsetenv(name) }
    #endif
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
