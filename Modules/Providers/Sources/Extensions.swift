import DataSources
import Kit
import Foundation

/// *Extensions* — `~/.claudebar/extensions/<id>/manifest.json`, read as
/// definitions of origin *Extension* (docs/features/extensions/design.md). The person's file
/// stays as it is: each section a definition can read becomes a data source,
/// and they answer together, as sections always did.
///
/// | Section | Becomes |
/// |---|---|
/// | `quotaGrid`, `costUsage` | `Fetch.script` from the extension's folder + `Mapping.usage` |
/// | `healthCheck` | a request; its failure shows as fetch health |
/// | `dailyUsage`, `metricsRow`, `statusBanner` | retired, and logged |
public enum Extensions {
    /// `~/.claudebar/extensions`.
    public static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claudebar/extensions", isDirectory: true)
    }

    /// Every extension in `root` that reads as a definition. One that doesn't
    /// is logged and left out — a broken folder never takes the others down.
    public static func catalog(in root: URL = folder) -> [ProviderDefinition] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                                                     options: [.skipsHiddenFiles])) ?? []
        return folders.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { folder in
            let manifest = folder.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifest) else { return nil }
            do {
                return try definition(manifest: data, folder: folder)
            } catch {
                AppLog.providers.error("Skipping extension \(folder.lastPathComponent): \(error.localizedDescription)")
                return nil
            }
        }
    }

    /// The definition an extension's manifest says, its scripts in `folder`.
    public static func definition(manifest data: Data, folder: URL) throws -> ProviderDefinition {
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        let settings = (manifest.config ?? []).map(\.setting)
        var sources: [DataSourceDefinition] = []
        for section in manifest.sections {
            switch section.type {
            case "quotaGrid", "costUsage":
                guard let command = section.probe.command else { continue }
                sources.append(DataSourceDefinition(
                    kind: section.id, label: section.id,
                    fetch: .script(ScriptCall(run: command, folder: folder.path,
                                              environment: Dictionary(uniqueKeysWithValues: (manifest.config ?? []).filter { !$0.isSecret }
                                                  .map { ($0.variable, "{{setting.\($0.id)}}") }),
                                              secrets: Dictionary(uniqueKeysWithValues: (manifest.config ?? []).filter(\.isSecret)
                                                  .map { ($0.variable, $0.id) }),
                                              timeout: section.probe.timeout ?? 10)),
                    mapping: .usage(UsageMapping())))
            case "healthCheck":
                guard let url = section.probe.url else { continue }
                sources.append(DataSourceDefinition(
                    kind: section.id, label: section.id,
                    fetch: .http(HTTPRequest(url: url, method: "HEAD", timeout: section.probe.timeout ?? 10)),
                    mapping: .text(TextMapping(quotas: []))))
            default:
                AppLog.providers.info("Extension \(manifest.id): its \(section.type) section is no longer read")
            }
        }
        guard let first = sources.first else {
            throw DefinitionError.noDataSources("ext-\(manifest.id)")
        }
        let json = try JSONEncoder().encode(ProviderDefinition(
            profile: ProviderProfile(
                id: "ext-\(manifest.id)", name: manifest.name,
                links: ProviderDefinition.Links(dashboard: manifest.dashboardURL.flatMap(URL.init(string:)),
                                                status: manifest.statusPageURL.flatMap(URL.init(string:))),
                look: ProviderLook(symbol: manifest.icon, color: manifest.colors?.primary.flatMap(Self.shades)),
                origin: .extension),
            dataSources: sources, defaultDataSource: first.kind, together: true, settings: settings))
        // Parsed like any definition, so it keeps every law a definition keeps.
        return try ProviderDefinition.parse(json, origin: .extension)
    }

    /// `#FF6B35` as the same colour in light and dark.
    private static func shades(_ hex: String) -> ProviderLook.Shades? {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = Int(digits, radix: 16) else { return nil }
        let rgb = ProviderLook.RGB(Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
        return ProviderLook.Shades(light: rgb, dark: rgb)
    }

    // MARK: - The manifest, as extensions write it

    private struct Manifest: Decodable {
        let id: String
        let name: String
        let icon: String?
        let colors: Colors?
        let dashboardURL: String?
        let statusPageURL: String?
        let config: [Field]?
        let sections: [Section]
    }

    private struct Colors: Decodable {
        let primary: String?
    }

    private struct Section: Decodable {
        let id: String
        let type: String
        let probe: Probe
    }

    private struct Probe: Decodable {
        let command: String?
        let url: String?
        let timeout: TimeInterval?
    }

    private struct Field: Decodable {
        let id: String
        let label: String
        let type: String
        let `default`: String?
        let options: [String]?

        var isSecret: Bool { type == "secret" }

        /// `apiKey` → `CLAUDEBAR_API_KEY`, `base-url` → `CLAUDEBAR_BASE_URL`: the
        /// names extension scripts read.
        var variable: String {
            let snake = id.replacingOccurrences(of: "-", with: "_")
                .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1_$2", options: .regularExpression)
            return "CLAUDEBAR_" + snake.uppercased()
        }

        var setting: Setting {
            let kind: Setting.Kind = switch type {
            case "secret": .secret
            case "number": .text(pattern: #"^-?[0-9]+(\.[0-9]+)?$"#)
            case "toggle": .choice([Setting.Option(id: "true", label: "On"), Setting.Option(id: "false", label: "Off")])
            case "choice": .choice((options ?? []).map { Setting.Option(id: $0) })
            case "path": .path(mustExist: false)
            default: .text(pattern: nil)
            }
            return Setting(id: id, label: label, kind: kind, default: self.default)
        }
    }
}
