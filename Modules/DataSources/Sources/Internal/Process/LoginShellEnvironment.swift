import Diagnostics
import Foundation

/// A variable as the person's login sets it. A GUI app may not inherit the
/// variables a shell profile exports, so it asks the OS's `LoginShell` to
/// print one between its markers, and reads it back.
public struct LoginShellEnvironment: Sendable {
    private let cliExecutor: any CLIExecutor
    private let shell: any LoginShell
    private let timeout: TimeInterval

    init(cliExecutor: any CLIExecutor, shell: any LoginShell, timeout: TimeInterval = 10.0) {
        self.cliExecutor = cliExecutor
        self.shell = shell
        self.timeout = timeout
    }

    /// The name comes from user settings and is interpolated into the command
    /// string, so only valid POSIX shell identifiers (ASCII) are allowed through.
    public static func isValidName(_ name: String) -> Bool {
        guard let first = name.first, (first.isASCII && first.isLetter) || first == "_" else { return false }
        return name.dropFirst().allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }

    /// Delimiters keep shell-profile output from being mistaken for the value.
    static let beginMarker = "@@CLAUDEBAR_BEGIN@@"
    static let endMarker = "@@CLAUDEBAR_END@@"

    /// Reads an environment variable from the user's login shell.
    /// Returns nil when the name is invalid, the lookup fails, or the variable is unset or empty.
    public func value(ofEnvVar name: String) async -> String? {
        guard Self.isValidName(name) else {
            AppLog.probes.debug("LoginShellEnvironment: invalid variable name, skipping login shell lookup")
            return nil
        }

        let argv = shell.command(printing: name, between: Self.beginMarker, and: Self.endMarker)
        guard let binary = argv.first else { return nil }

        do {
            let result = try await cliExecutor.execute(
                binary: binary,
                args: Array(argv.dropFirst()),
                input: nil,
                timeout: timeout,
                workingDirectory: nil,
                autoResponses: [:]
            )
            return Self.parse(result.output, exitCode: result.exitCode, name: name)
        } catch {
            AppLog.probes.debug("LoginShellEnvironment: login shell lookup for \(name) failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func parse(_ output: String, exitCode: Int32, name: String) -> String? {
        guard exitCode == 0 else {
            AppLog.probes.debug("LoginShellEnvironment: lookup for \(name) exited with \(exitCode)")
            return nil
        }

        guard let begin = output.range(of: beginMarker),
              let end = output.range(of: endMarker, range: begin.upperBound..<output.endIndex) else {
            AppLog.probes.debug("LoginShellEnvironment: markers missing from shell output for \(name)")
            return nil
        }

        let value = String(output[begin.upperBound..<end.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            AppLog.probes.debug("LoginShellEnvironment: \(name) is not set in login shell")
            return nil
        }
        return value
    }
}
