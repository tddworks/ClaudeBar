import Foundation
import DataSources

/// Environment variables as the user's shell sees them. An app started from
/// Finder, the Dock or Login Items doesn't inherit what `~/.zshrc` exports, so
/// a variable missing from the app's own environment is read from the login
/// shell (#170). A value found there is kept for the session; a miss is asked
/// again, so a key exported later is found without a restart.
///
/// The lookup blocks its caller for up to the shell's timeout, so give it only
/// to a credential lookup that reaches the environment last.
public final class ShellEnvironment: @unchecked Sendable {
    private let process: [String: String]
    private let shell: LoginShellEnvironment
    private let lock = NSLock()
    private var found: [String: String] = [:]

    public init(process: [String: String] = ProcessInfo.processInfo.environment,
                cliExecutor: any CLIExecutor = DefaultCLIExecutor()) {
        self.process = process
        self.shell = LoginShellEnvironment(cliExecutor: cliExecutor)
    }

    public func value(_ name: String) -> String? {
        if let value = process[name], !value.isEmpty { return value }
        if let value = lock.withLock({ found[name] }) { return value }
        guard let value = Self.wait({ [shell] in await shell.value(ofEnvVar: name) }) else { return nil }
        lock.withLock { found[name] = value }
        return value
    }

    /// The credential lookup is synchronous; the shell is not.
    private static func wait(_ work: @escaping @Sendable () async -> String?) -> String? {
        let done = DispatchSemaphore(value: 0)
        let result = Box()
        Task.detached {
            result.value = await work()
            done.signal()
        }
        // The shell has its own 10-second timeout; this only guards against a
        // lookup that never gets a thread.
        guard done.wait(timeout: .now() + 15) == .success else { return nil }
        return result.value
    }

    private final class Box: @unchecked Sendable { var value: String? }
}
