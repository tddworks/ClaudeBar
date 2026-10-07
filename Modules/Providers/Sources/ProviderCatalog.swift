import Kit
import Foundation

/// Where definitions live, and the one place they are found
/// (TARGET_ARCHITECTURE §10): the app bundle, the providers people make in
/// `~/.claudebar/providers/<id>.json` (origin **custom**), and extensions in
/// `~/.claudebar/extensions`. A definition on disk is a provider; no Swift
/// lists one. Keys never live here — a definition names a key
/// (`"setting": "apiKey"`), the vault holds it.
public struct ProviderCatalog: Sendable {
    public let directory: URL
    public let extensions: URL

    public init(directory: URL = ProviderCatalog.userDirectory, extensions: URL = Extensions.folder) {
        self.directory = directory
        self.extensions = extensions
    }

    /// Every definition, built-in, custom and extension, in lineup order:
    /// by each one's `order`, then by name. A built-in's id is the
    /// built-in's — another file using it is left out. A file that doesn't
    /// parse is logged and left out; the rest load.
    public func detect() -> [ProviderDefinition] {
        let builtIns = Array(ProviderFactory.builtInDefinitions.values)
        let reserved = Set(builtIns.map(\.id))
        let others = (custom() + Extensions.catalog(in: extensions)).filter { definition in
            guard reserved.contains(definition.id) else { return true }
            AppLog.providers.error("Skipping \(definition.id) from \(definition.profile.origin.rawValue): a built-in has that id")
            return false
        }
        var seen = Set<String>()
        return (builtIns + others)
            .filter { seen.insert($0.id).inserted }
            .sorted { ($0.order ?? .max, $0.profile.name.lowercased(), $0.id) < ($1.order ?? .max, $1.profile.name.lowercased(), $1.id) }
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
        guard ProviderFactory.builtInDefinitions[definition.id] == nil else {
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
            if ProviderFactory.builtInDefinitions[id] == nil, !FileManager.default.fileExists(atPath: file(for: id).path) {
                return id
            }
        }
    }

    private func file(for id: String) -> URL {
        directory.appendingPathComponent("\(id).json")
    }
}
