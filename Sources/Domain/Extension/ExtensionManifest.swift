import Quotas
import DataSources
import Providers
import Foundation

/// Represents a parsed extension manifest (manifest.json).
/// Each extension defines one or more sections, each with its own probe command.
public struct ExtensionManifest: Sendable, Equatable {
    public let id: String
    public let name: String
    public let version: String
    public let description: String?
    public let icon: String?
    public let colors: ExtensionColors?
    public let dashboardURL: URL?
    public let statusPageURL: URL?
    public let configFields: [ConfigField]
    public let sections: [ExtensionSection]

    /// Whether this extension declares any user-configurable fields.
    public var hasConfig: Bool { !configFields.isEmpty }

    public init(
        id: String,
        name: String,
        version: String,
        description: String? = nil,
        icon: String? = nil,
        colors: ExtensionColors? = nil,
        dashboardURL: URL? = nil,
        statusPageURL: URL? = nil,
        configFields: [ConfigField] = [],
        sections: [ExtensionSection]
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.icon = icon
        self.colors = colors
        self.dashboardURL = dashboardURL
        self.statusPageURL = statusPageURL
        self.configFields = configFields
        self.sections = sections
    }

    /// Parses a manifest from JSON data.
    public static func parse(from data: Data) throws -> ExtensionManifest {
        let decoder = JSONDecoder()
        let raw = try decoder.decode(RawManifest.self, from: data)

        guard !raw.sections.isEmpty else {
            throw ExtensionManifestError.emptySections
        }

        let sections = try raw.sections.map { rawSection -> ExtensionSection in
            guard let type = SectionType(rawValue: rawSection.type) else {
                throw ExtensionManifestError.unknownSectionType(rawSection.type)
            }

            let probeConfig: ProbeConfig
            if let builtIn = rawSection.probe.builtIn, builtIn == "healthCheck",
               let urlString = rawSection.probe.url,
               let url = URL(string: urlString) {
                probeConfig = .healthCheck(url: url)
            } else if let command = rawSection.probe.command {
                probeConfig = .script(command)
            } else {
                throw ExtensionManifestError.invalidProbeConfig(rawSection.id)
            }

            return ExtensionSection(
                id: rawSection.id,
                type: type,
                probeConfig: probeConfig,
                refreshInterval: rawSection.probe.interval ?? 60,
                timeout: rawSection.probe.timeout ?? 10
            )
        }

        return ExtensionManifest(
            id: raw.id,
            name: raw.name,
            version: raw.version,
            description: raw.description,
            icon: raw.icon,
            colors: raw.colors,
            dashboardURL: raw.dashboardURL.flatMap { URL(string: $0) },
            statusPageURL: raw.statusPageURL.flatMap { URL(string: $0) },
            configFields: raw.config ?? [],
            sections: sections
        )
    }
}

// MARK: - Supporting Types

public struct ExtensionColors: Sendable, Equatable, Codable {
    public let primary: String
    public let gradient: [String]?

    public init(primary: String, gradient: [String]? = nil) {
        self.primary = primary
        self.gradient = gradient
    }
}

public enum ExtensionManifestError: Error, LocalizedError {
    case emptySections
    case unknownSectionType(String)
    case invalidProbeConfig(String)

    public var errorDescription: String? {
        switch self {
        case .emptySections:
            "Extension manifest must have at least one section"
        case .unknownSectionType(let type):
            "Unknown section type: '\(type)'"
        case .invalidProbeConfig(let sectionId):
            "Section '\(sectionId)' must have either 'command' or 'builtIn' + 'url' in probe config"
        }
    }
}

// MARK: - Raw JSON Decoding Types

private struct RawManifest: Codable {
    let id: String
    let name: String
    let version: String
    let description: String?
    let icon: String?
    let colors: ExtensionColors?
    let dashboardURL: String?
    let statusPageURL: String?
    let config: [ConfigField]?
    let sections: [RawSection]
}

private struct RawSection: Codable {
    let id: String
    let type: String
    let probe: RawProbe
}

private struct RawProbe: Codable {
    let command: String?
    let builtIn: String?
    let url: String?
    let interval: TimeInterval?
    let timeout: TimeInterval?
}
