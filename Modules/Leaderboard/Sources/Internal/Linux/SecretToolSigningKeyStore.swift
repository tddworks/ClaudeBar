#if os(Linux)
import Diagnostics
import Foundation

/// The key in the person's secret store through libsecret's `secret-tool`: a
/// generic secret under a service and an account, its value the key as base64,
/// named as the Mac's Keychain item is.
///
/// When `secret-tool` isn't installed, or no secret service is running —
/// a container, a bare session — nothing is kept and nothing is lost:
/// `FallbackSigningKeyStore` keeps the key in the app's own store instead.
struct SecretToolSigningKeyStore: SigningKeyStore {
    var service = "com.tddworks.claudebar.credentials"
    var account = "leaderboard-signing-key"

    func load() -> Data? {
        let answer = run(["lookup", "service", service, "account", account], input: nil)
        guard answer.status == 0 else { return nil }
        let text = answer.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : Data(base64Encoded: text)
    }

    func save(_ rawKey: Data) {
        let answer = run(["store", "--label", "ClaudeBar leaderboard key",
                          "service", service, "account", account],
                         input: Data(rawKey.base64EncodedString().utf8))
        if answer.status != 0 { logFailure("store", answer.status) }
    }

    func delete() {
        let answer = run(["clear", "service", service, "account", account], input: nil)
        // `clear` exits non-zero when there was nothing to clear, which is not
        // a failure; anything it printed on stderr is.
        if answer.status != 0 && !answer.errors.isEmpty { logFailure("clear", answer.status) }
    }

    /// Runs `secret-tool` with both pipes drained, as the Mac's keychain store
    /// runs `security`. `/usr/bin/env` finds the tool on the person's `PATH`;
    /// when it isn't there, `env` exits 127 and nothing is kept.
    ///
    /// The secret is put in the pipe *before* the tool starts, never after:
    /// writing to a tool that has already gone — `env` exiting 127 when
    /// `secret-tool` isn't installed — is a write to a pipe with no reader, and
    /// `SIGPIPE`'s default action ends the whole app, not just this call. A
    /// pipe holds the secret until the tool reads it, and closing the write end
    /// first is what tells it there is no more.
    private func run(_ arguments: [String], input: Data?) -> (status: Int32, output: String, errors: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["secret-tool"] + arguments
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        if let input {
            let inputPipe = Pipe()
            inputPipe.fileHandleForWriting.write(input)
            try? inputPipe.fileHandleForWriting.close()
            process.standardInput = inputPipe
        } else {
            process.standardInput = FileHandle.nullDevice
        }
        do {
            try process.run()
        } catch {
            AppLog.credentials.error("secret-tool could not start")
            return (-1, "", "")
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus,
                String(decoding: data, as: UTF8.self),
                String(decoding: errorData, as: UTF8.self))
    }

    private func logFailure(_ operation: String, _ status: Int32) {
        // Never the key: only that the store would not take it.
        AppLog.credentials.error("Secret store \(operation) failed with status \(status)")
    }
}
#endif
