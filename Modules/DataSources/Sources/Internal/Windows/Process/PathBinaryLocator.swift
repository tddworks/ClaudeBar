#if os(Windows)
import Foundation

/// Finds a CLI on Windows' `PATH` as `where` does: each folder in order, the
/// name as given when it has an extension, else with each extension `PATHEXT`
/// lists. A path to the CLI, such as the one a provider's CLI location
/// gives, is taken as it is when the file is there, as the Mac's locator
/// takes one, and never searched for.
struct PathBinaryLocator: Sendable {
    var environment: @Sendable () -> [String: String] = { ProcessInfo.processInfo.environment }

    func locate(_ cli: String) -> String? {
        let environment = environment()
        // Windows' variable names ignore case: `Path` is the usual spelling.
        func variable(_ name: String) -> String? {
            environment.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
        let extensions = (variable("PATHEXT") ?? ".COM;.EXE;.BAT;.CMD").split(separator: ";").map(String.init)
        let names = URL(fileURLWithPath: cli).pathExtension.isEmpty ? extensions.map { cli + $0.lowercased() } : [cli]
        if cli.contains("\\") || cli.contains("/") {
            return names.first(where: Self.isFile)
        }
        let folders = (variable("PATH") ?? "").split(separator: ";").map(String.init).filter { !$0.isEmpty }
        for folder in folders {
            for name in names {
                let path = URL(fileURLWithPath: folder, isDirectory: true).appendingPathComponent(name).path
                if Self.isFile(path) { return path }
            }
        }
        return nil
    }

    private static func isFile(_ path: String) -> Bool {
        var isFolder: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isFolder) && !isFolder.boolValue
    }
}
#endif
