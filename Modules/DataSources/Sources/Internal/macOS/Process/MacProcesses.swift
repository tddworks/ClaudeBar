#if os(macOS)
import Diagnostics
import Foundation
import Quotas

/// The Mac's `Processes`: a CLI found through the login shell's `PATH`,
/// programs run over swift-subprocess at the fetch's quality of service,
/// children ended with `SIGTERM` then `SIGKILL`, the kernel's process table,
/// and the person's login shell.
struct MacProcesses: Processes {
    func locate(_ cli: String) -> String? {
        BinaryLocator.which(cli)
    }

    func runner(_ change: ProcessEnvironment) -> any CLIExecutor {
        PipeCLIExecutor(change: change, facts: Self.facts)
    }

    func converse(_ executable: String, _ arguments: [String], _ environment: [String: String]?,
                  _ directory: URL?) throws -> any RPCTransport {
        guard let path = BinaryLocator.which(executable) else {
            AppLog.probes.error("RPC transport: '\(executable)' not found in PATH")
            AppLog.probes.debug("Shell PATH: \(BinaryLocator.shellPath())")
            throw UsageError.cliNotFound(executable)
        }
        var environment = environment ?? ProcessInfo.processInfo.environment
        environment["PATH"] = BinaryLocator.shellPath()
        return try PipeConversation(executablePath: path, arguments: arguments, environment: environment,
                                    directory: directory, end: Self.facts.end)
    }

    func running() -> [String] {
        RunningProcesses.system()
    }

    // A script is a path, not shell source; positional argv preserves spaces,
    // quotes and metacharacters in the resolved filename.
    func script(_ path: String) -> [String] {
        ["/bin/sh", "-c", "exec \"$1\"", "claudebar-script", path]
    }

    func loginVariable(_ variable: String) -> [String] {
        let preferred = ProcessInfo.processInfo.environment["SHELL"] ?? ""
        let binary = preferred.isEmpty ? "/bin/zsh" : preferred
        // An interactive login shell sources both rc and profile files.
        let command = "printf '\(LoginShellEnvironment.beginMarker)%s\(LoginShellEnvironment.endMarker)\\n' \"$\(variable)\""
        return [binary, "-l", "-i", "-c", command]
    }

    static let facts = PipeFacts(
        locate: { BinaryLocator.which($0) },
        environment: { path, change in environment(binaryPath: path, change: change) },
        end: { process in ChildTeardown.end(process, named: process.executableURL?.lastPathComponent ?? "RPC child") }
    )

    /// The app's environment with a PATH that finds tools outside a login
    /// shell — an app started by launchd gets a minimal one, which breaks a
    /// script whose shebang is `/usr/bin/env node` — then the call's changes.
    static func environment(binaryPath: String, change: ProcessEnvironment) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        var entries = (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":").map(String.init)
        var seen = Set(entries)
        let ownDirectory = URL(fileURLWithPath: binaryPath).deletingLastPathComponent().path
        for directory in [ownDirectory] + BinaryLocator.commonPaths where seen.insert(directory).inserted {
            entries.append(directory)
        }
        environment["PATH"] = entries.joined(separator: ":")
        for name in change.unset { environment.removeValue(forKey: name) }
        environment.merge(change.set) { _, value in value }
        return environment
    }
}
#endif
