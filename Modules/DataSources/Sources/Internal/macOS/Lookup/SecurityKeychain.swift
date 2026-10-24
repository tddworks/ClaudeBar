#if os(macOS)
import Foundation

/// The Mac's secret store: its Keychain, asked through the `security` tool.
/// A password is answered as `security -w` prints it; with no account, a save
/// names the person, as Claude Code's own item does.
struct SecurityKeychain: KeychainItems {
    /// Runs `security` with these arguments: exit status and stdout.
    typealias Run = @Sendable (_ arguments: [String]) -> (status: Int32, output: String)

    var run: Run = SecurityKeychain.system

    func password(service: String, account: String?) -> String? {
        let named = account.map { ["-a", $0] } ?? []
        let (status, output) = run(["find-generic-password", "-s", service] + named + ["-w"])
        return status == 0 ? output : nil
    }

    func save(_ password: String, service: String, account: String?) -> Bool {
        run(["add-generic-password", "-U", "-s", service, "-a", account ?? NSUserName(), "-w", password]).status == 0
    }

    /// The real `/usr/bin/security`, run synchronously with both pipes drained.
    static let system: Run = { arguments in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            _ = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        } catch {
            return (-1, "")
        }
    }
}
#endif
