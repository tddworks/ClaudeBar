import ClaudeBarKit
import Foundation

/// `~/.claudebar/settings.json`, read and written by dotted name (`app.themeMode`) — the
/// Swift face of Kotlin's `SettingsFile`, which owns the file, its lock and its format.
/// Values cross as JSON text and arrive as Foundation values (`String`, `Bool`, `[String]` …).
public final class JSONSettingsStore: @unchecked Sendable {
    /// The default file.
    public static let shared = JSONSettingsStore()

    public let fileURL: URL
    private let file: SettingsFile

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.file = SettingsFile(path: self.fileURL.path)
    }

    /// The setting under a dotted name, if it exists and is a `T`.
    public func read<T>(key: String) -> T? {
        guard let json = file.readJson(key: key) else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(json.utf8), options: .fragmentsAllowed)) as? T
    }

    /// Saves a setting under a dotted name; `nil` forgets it.
    public func write(value: Any?, key: String) {
        guard let value else { return file.writeJson(key: key, json: nil) }
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed) else { return }
        file.writeJson(key: key, json: String(decoding: data, as: UTF8.self))
    }

    /// Every setting in the file.
    public func readAll() -> [String: Any] {
        let json = file.readAllJson()
        return (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
    }

    public static func defaultFileURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claudebar/settings.json")
    }
}

extension SettingsFile: @retroactive @unchecked Sendable {}
