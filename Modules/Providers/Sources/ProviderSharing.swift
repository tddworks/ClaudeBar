import DataSources
import Foundation

extension ProviderDefinition {
    /// *Export…* — the definition as a file to share. A key is only ever a
    /// NAME in a definition (`"setting": "apiKey"`); its value lives in the
    /// vault, so no exported file holds one (USER_JOURNEYS F9). The origin is
    /// left out: whoever imports it decides.
    public func exported() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// *Key needed* — the settings this definition asks whoever adds it for.
    public var neededSettings: [String] {
        Array(Set(dataSources.flatMap { $0.credential.map(Self.keyNames(in:)) ?? [] })).sorted()
    }

    /// Where it sends a key — the host of every URL a data source with a
    /// credential may call, with each setting's every option spelled out, so
    /// a region a person might pick later is listed too.
    public var keyDestinations: [String] {
        let urls = dataSources.filter { $0.credential != nil }.flatMap(\.fetch.connection.urls)
        return Array(Set(urls.flatMap(expandingSettings).map { URL(string: $0)?.host ?? $0 })).sorted()
    }

    /// Every command it runs, as typed.
    public var commands: [String] {
        var seen = Set<String>()
        return dataSources.flatMap(\.fetch.connection.commands)
            .map { $0.joined(separator: " ") }
            .filter { seen.insert($0).inserted }
    }

    /// `text` once for each value its `{{setting.x}}` placeholders can take.
    private func expandingSettings(_ text: String) -> [String] {
        settings.reduce([text]) { texts, setting in texts.flatMap(setting.expanding) }
    }

    private static func keyNames(in lookup: CredentialLookup) -> [String] {
        switch lookup {
        case .setting(let name): [name]
        case .firstOf(let lookups): lookups.flatMap(keyNames(in:))
        case .refreshing(let base, _), .refined(let base, _): keyNames(in: base)
        case .environment, .jsonFile, .keychain, .browserCookies, .sqlite: []
        }
    }
}

/// *Import provider* — what a shared file would do, shown BEFORE anything is
/// saved or run (USER_JOURNEYS F10).
public struct ImportReview: Sendable, Equatable {
    /// As it will be saved: origin custom, its id kept unless taken.
    public let definition: ProviderDefinition
    /// "It will send your key to that address."
    public let sendsKeyTo: [String]
    /// The commands it runs — a person agrees to them first.
    public let runs: [String]
    /// "Key needed".
    public let needs: [String]
}

extension ProviderCatalog {
    /// Reads a shared file and says what it would do. Its id is kept unless a
    /// built-in or a saved provider already has it; then it gets a new one.
    public func review(_ file: Data) throws -> ImportReview {
        var definition = try ProviderDefinition.parse(file, origin: .custom)
        if Providers.builtInDefinitions[definition.id] != nil || custom().contains(where: { $0.id == definition.id }) {
            definition = definition.renamed(id: mintId(for: definition.profile.name))
        }
        return ImportReview(
            definition: definition,
            sendsKeyTo: definition.keyDestinations,
            runs: definition.commands,
            needs: definition.neededSettings
        )
    }

    /// *Add*: saves what the review showed.
    @discardableResult
    public func `import`(_ review: ImportReview) throws -> ProviderDefinition {
        try add(review.definition)
        return review.definition
    }
}

extension ProviderDefinition {
    /// The same definition under another id, as custom.
    func renamed(id: String) -> ProviderDefinition {
        ProviderDefinition(
            profile: ProviderProfile(id: id, name: profile.name, links: profile.links, look: profile.look, origin: .custom),
            cli: cli,
            enabledByDefault: enabledByDefault,
            dataSources: dataSources,
            defaultDataSource: defaultDataSource,
            accounts: accounts,
            settings: settings,
            usageHistory: usageHistory
        )
    }
}
