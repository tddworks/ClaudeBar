import Foundation
import Kit

/// Persists imported terminal color schemes as JSON files in `~/.claudebar/themes/`.
///
/// On load, the stored ``TerminalColorScheme`` values are re-generated into themes
/// by ``TerminalThemeGenerator``, ensuring imported themes benefit from future mapping improvements.
@MainActor
public final class ImportedThemeStore {

    private let themesDirectory: URL

    /// Create a store backed by a directory.
    /// - Parameter directory: Override for the themes directory. Defaults to `~/.claudebar/themes/`.
    public init(directory: URL? = nil) {
        self.themesDirectory = directory ?? Self.defaultDirectory()
    }

    /// Load all imported color schemes from disk, sorted by import date.
    public func loadAll() -> [(TerminalColorScheme, Date)] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: themesDirectory, includingPropertiesForKeys: nil
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> (TerminalColorScheme, Date)? in
                guard let data = try? Data(contentsOf: url),
                      let entry = try? JSONDecoder().decode(StoredTheme.self, from: data)
                else { return nil }
                return (entry.scheme, entry.importedAt)
            }
    }

    /// Save a color scheme to disk as JSON.
    public func save(_ scheme: TerminalColorScheme) throws {
        try FileManager.default.createDirectory(at: themesDirectory, withIntermediateDirectories: true)
        let entry = StoredTheme(scheme: scheme, importedAt: Date())
        let data = try JSONEncoder().encode(entry)
        let filename = Self.sanitize(scheme.name)
        let fileURL = themesDirectory.appendingPathComponent("\(filename).json")
        try data.write(to: fileURL, options: .atomic)
    }

    /// Delete a stored theme by its scheme name.
    public func delete(name: String) throws {
        let filename = Self.sanitize(name)
        let fileURL = themesDirectory.appendingPathComponent("\(filename).json")
        try FileManager.default.removeItem(at: fileURL)
    }

    private static func defaultDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claudebar")
            .appendingPathComponent("themes")
    }

    private static func sanitize(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[^a-z0-9\\-]", with: "", options: .regularExpression)
    }

    private struct StoredTheme: Codable {
        let scheme: TerminalColorScheme
        let importedAt: Date
    }
}
