import Foundation

/// Thread-safe JSON file I/O primitive for settings storage.
/// Supports dot-notation keys for nested access (e.g., "app.themeMode").
/// Preserves unknown keys on write (OCP-compliant).
///
/// File location: `~/.claudebar/settings.json` (default)
public final class JSONSettingsStore: @unchecked Sendable {

    /// Shared instance using the default file path
    public static let shared = JSONSettingsStore()

    public let fileURL: URL
    private let lock = NSLock()

    /// Creates a store backed by a JSON file.
    /// - Parameter fileURL: Path to settings file. Defaults to `~/.claudebar/settings.json`.
    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
    }

    // MARK: - Public API

    /// Reads a value for the given key path (dot-notation supported).
    /// Returns nil if key doesn't exist, file is missing, or type doesn't match.
    public func read<T>(key: String) -> T? {
        let dict = readFile()
        return resolveRead(dict: dict, keyPath: key.split(separator: ".").map(String.init)) as? T
    }

    /// Writes a value for the given key path (dot-notation supported).
    /// Pass nil to remove the key. Creates the file and parent directories if needed.
    public func write(value: Any?, key: String) {
        lock.lock()
        defer { lock.unlock() }

        var dict = readFileUnsafe()
        let parts = key.split(separator: ".").map(String.init)
        resolveWrite(dict: &dict, keyPath: parts, value: value)
        writeFile(dict)
    }

    /// Returns the full settings dictionary (for migration/debugging).
    public func readAll() -> [String: Any] {
        readFile()
    }

    // MARK: - Default Path

    public static func defaultFileURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claudebar/settings.json")
    }

    // MARK: - File I/O

    private func readFile() -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        return readFileUnsafe()
    }

    /// Must be called while holding the lock.
    private func readFileUnsafe() -> [String: Any] {
        guard let data = try? Data(contentsOf: fileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    /// Must be called while holding the lock.
    private func writeFile(_ dict: [String: Any]) {
        let parentDir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: - Key Path Resolution

    private func resolveRead(dict: [String: Any], keyPath: [String]) -> Any? {
        guard let first = keyPath.first else { return nil }

        if keyPath.count == 1 {
            return dict[first]
        }

        guard let nested = dict[first] as? [String: Any] else { return nil }
        return resolveRead(dict: nested, keyPath: Array(keyPath.dropFirst()))
    }

    private func resolveWrite(dict: inout [String: Any], keyPath: [String], value: Any?) {
        guard let first = keyPath.first else { return }

        if keyPath.count == 1 {
            if let value = value {
                dict[first] = value
            } else {
                dict.removeValue(forKey: first)
            }
            return
        }

        var nested = (dict[first] as? [String: Any]) ?? [:]
        resolveWrite(dict: &nested, keyPath: Array(keyPath.dropFirst()), value: value)
        dict[first] = nested
    }
}
