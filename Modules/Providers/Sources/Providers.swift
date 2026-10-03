import DataSources
import Quotas
import Foundation
import Synchronization

/// The module's factory: definition → `Provider`, its data sources made live
/// by `DataSources.make`. The App composes with this and never names a worker.
public enum Providers {
    /// A built-in definition, shipped in this module's `Resources/Providers/`.
    public static func builtIn(_ id: String) throws -> ProviderDefinition {
        try ProviderDefinition.parse(try builtInData(id))
    }

    /// The built-in definition's JSON, as shipped.
    public static func builtInData(_ id: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: id, withExtension: "json") else {
            throw DefinitionError.missingFile(id)
        }
        return try Data(contentsOf: url)
    }

    /// Every built-in definition, by id — read once from `Resources/Providers/`.
    public static let builtInDefinitions: [String: ProviderDefinition] = {
        let urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        var definitions: [String: ProviderDefinition] = [:]
        for url in urls {
            guard let data = try? Data(contentsOf: url), let definition = try? ProviderDefinition.parse(data) else { continue }
            definitions[definition.id] = definition
        }
        return definitions
    }()

    /// The built-in definition a lineup id belongs to — `codex.<account>`
    /// belongs to `codex`. What screens that only hold an id use for a face.
    public static func builtInDefinition(forLineupId id: String) -> ProviderDefinition? {
        builtInDefinitions[id] ?? id.split(separator: ".", maxSplits: 1).first.flatMap { builtInDefinitions[String($0)] }
    }

    /// The custom definitions in use — what `definition(forLineupId:)` finds
    /// after the built-ins. Set when the app loads them, and on *Save* / *Delete*.
    private static let customDefinitions = Mutex<[String: ProviderDefinition]>([:])

    public static func register(custom definition: ProviderDefinition) {
        customDefinitions.withLock { $0[definition.id] = definition }
    }

    public static func unregister(custom id: String) {
        customDefinitions.withLock { $0[id] = nil }
    }

    /// The definition — built in, then custom — a lineup id belongs to.
    public static func definition(forLineupId id: String) -> ProviderDefinition? {
        if let builtIn = builtInDefinition(forLineupId: id) { return builtIn }
        let base = id.split(separator: ".", maxSplits: 1).first.map(String.init) ?? id
        return customDefinitions.withLock { $0[id] ?? $0[base] }
    }

    /// A mapping script shipped beside the built-in definitions.
    public static let builtInScripts: DataSources.ScriptSource = { file in
        let name = (file as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension
        guard let url = Bundle.module.url(forResource: name, withExtension: ext.isEmpty ? "js" : ext) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// A provider on the real network, CLI, Keychain and file system, with
    /// its default login and every login in `accounts`.
    @MainActor
    public static func make(
        _ definition: ProviderDefinition,
        settings: any MultiAccountSettingsRepository,
        accounts: [ProviderAccountConfig] = [],
        secrets: (any SecretVault)? = nil,
        guestPasses: GuestPasses? = nil,
        usageHistory: UsageHistory? = nil,
        environment: @escaping @Sendable (String) -> String? = { ProcessInfo.processInfo.environment[$0] },
        cloudWatch: (any CloudWatchClient)? = nil,
        priceCatalog: (any PriceCatalog)? = nil
    ) -> Provider {
        Provider(
            definition: definition,
            settings: settings,
            accounts: accounts,
            makeDataSource: { source, login in
                DataSources.make(source, providerId: definition.id, scripts: builtInScripts, secrets: secrets?.scoped(to: login),
                                 environment: environment, cloudWatch: cloudWatch, priceCatalog: priceCatalog)
            },
            guestPasses: guestPasses,
            // The definition says how to read the default login's logs.
            usageHistory: usageHistory ?? definition.usageHistory.map {
                UsageHistory(log: DataSources.makeUsageLog($0, scripts: builtInScripts, environment: environment))
            },
            vault: secrets
        )
    }

    /// A built-in provider by id — `Providers.make("codex", settings:)`.
    @MainActor
    public static func make(
        _ id: String,
        settings: any MultiAccountSettingsRepository,
        accounts: [ProviderAccountConfig] = [],
        secrets: (any SecretVault)? = nil,
        guestPasses: GuestPasses? = nil,
        usageHistory: UsageHistory? = nil,
        environment: @escaping @Sendable (String) -> String? = { ProcessInfo.processInfo.environment[$0] },
        cloudWatch: (any CloudWatchClient)? = nil,
        priceCatalog: (any PriceCatalog)? = nil
    ) throws -> Provider {
        make(try builtIn(id), settings: settings, accounts: accounts, secrets: secrets, guestPasses: guestPasses,
             usageHistory: usageHistory, environment: environment,
             cloudWatch: cloudWatch, priceCatalog: priceCatalog)
    }
}
