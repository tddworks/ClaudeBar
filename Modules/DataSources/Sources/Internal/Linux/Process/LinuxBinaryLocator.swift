#if os(Linux)
import Foundation

/// Finds a CLI on Linux's `PATH`: each folder in order, the name as given. A
/// path to the CLI, such as the one a provider's CLI location gives, is taken
/// as it is when the file is executable, and never searched for.
///
/// Named for Linux, as `WindowsTimeZone` is for Windows: SwiftPM names each
/// file's object after the file, so two platforms' files can't share one.
struct LinuxBinaryLocator: Sendable {
    var environment: @Sendable () -> [String: String] = { ProcessInfo.processInfo.environment }

    func locate(_ cli: String) -> String? {
        if cli.contains("/") {
            return FileManager.default.isExecutableFile(atPath: cli) ? cli : nil
        }
        let folders = (environment()["PATH"] ?? "").split(separator: ":").map(String.init).filter { !$0.isEmpty }
        for folder in folders {
            let path = URL(fileURLWithPath: folder, isDirectory: true).appendingPathComponent(cli).path
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }
}
#endif
