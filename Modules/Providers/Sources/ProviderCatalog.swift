import Diagnostics
import Foundation

/// Where the providers people make live: `~/.claudebar/providers/<id>.json`,
/// one definition per file, origin **custom**. Keys never live here — a
/// definition names a key (`"setting": "apiKey"`), the vault holds it.
public struct ProviderCatalog: Sendable {
    public let directory: URL

    public init(directory: URL = ProviderCatalog.userDirectory) {
        self.directory = directory
    }

    /// `~/.claudebar/providers`.
    public static var userDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claudebar", isDirectory: true)
            .appendingPathComponent("providers", isDirectory: true)
    }

    /// Every custom definition that parses, by id. One that doesn't is
    /// skipped and logged — a broken file never takes the others down.
    public func custom() -> [ProviderDefinition] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { url in
            do {
                return try ProviderDefinition.parse(Data(contentsOf: url), origin: .custom)
            } catch {
                AppLog.providers.error("Skipping custom provider \(url.lastPathComponent): \(error.localizedDescription)")
                return nil
            }
        }
    }

    /// *Save*: writes the definition. A built-in's id is refused.
    public func add(_ definition: ProviderDefinition) throws {
        guard Providers.builtInDefinitions[definition.id] == nil else {
            throw DefinitionError.duplicateProvider(definition.id)
        }
        try definition.validate()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(definition).write(to: file(for: definition.id), options: .atomic)
        AppLog.providers.info("Saved custom provider \(definition.id)")
    }

    /// *Delete*: removes the definition's file.
    public func remove(_ id: String) throws {
        let url = file(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
        AppLog.providers.info("Removed custom provider \(id)")
    }

    /// A new id, minted once: `custom-<name>-<random>` — stable forever,
    /// never derived from the name alone, never a built-in's or a saved one's.
    public func mintId(for name: String) -> String {
        let slug = name.lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { result, character in
                if character != "-" || result.last != "-" { result.append(character) }
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        while true {
            let id = "custom-\(slug.isEmpty ? "provider" : slug)-\(UUID().uuidString.prefix(6).lowercased())"
            if Providers.builtInDefinitions[id] == nil, !FileManager.default.fileExists(atPath: file(for: id).path) {
                return id
            }
        }
    }

    private func file(for id: String) -> URL {
        directory.appendingPathComponent("\(id).json")
    }
}
