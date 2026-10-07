import DataSources
import Kit
import Foundation
import Observation

/// *Providers* — the providers you keep: the Settings → Providers pane
/// (TARGET §2.1). It creates a custom provider, reads them and the
/// lineup, keeps their order and deletes a custom one. The Monitor holds it
/// and only watches; a login added to a provider is the provider's own
/// business, never this collection's.
@MainActor
@Observable
public final class Providers {
    /// Every provider, in the pane's order.
    public private(set) var all: [Provider]

    @ObservationIgnored private let settings: (any ProviderSettingsRepository)?
    @ObservationIgnored private let catalog: ProviderCatalog
    @ObservationIgnored private let vault: (any SecretVault)?
    @ObservationIgnored private let make: (ProviderDefinition) -> Provider

    /// - Parameter make: makes a definition live — the real connections in
    ///   the app, stubbed ones in tests.
    public init(_ providers: [Provider],
                settings: (any ProviderSettingsRepository)? = nil,
                catalog: ProviderCatalog = ProviderCatalog(),
                vault: (any SecretVault)? = nil,
                make: @escaping (ProviderDefinition) -> Provider) {
        self.settings = settings
        self.catalog = catalog
        self.vault = vault
        self.make = make
        let unique = providers.reduce(into: [Provider]()) { kept, provider in
            if !kept.contains(where: { $0.id == provider.id }) { kept.append(provider) }
        }
        self.all = Self.ordered(unique, by: settings?.providerOrder() ?? [])
    }

    // MARK: - Read

    /// Every login of every provider, on or off, in the pane's order.
    public var logins: [Account] { all.flatMap(\.accounts) }

    /// The enabled logins of enabled providers, in the pane's order — what
    /// the pills, the menu bar, refreshes and alerts show. Derived, never kept.
    public var lineup: [Account] { all.flatMap { provider in provider.accounts.filter(provider.isInLineup) } }

    public func provider(id: String) -> Provider? { all.first { $0.id == id } }

    /// A login by its lineup id — `claude`, `codex.<acct>`.
    public func login(id: String) -> Account? { logins.first { $0.id == id } }

    /// A login's product — found by the id the login names, `nil` once it is
    /// gone. The way to ask anything product-level about a login (TARGET §2.1:
    /// a login never refers to its provider).
    public func provider(of account: Account) -> Provider? { provider(id: account.providerId) }

    // MARK: - Create

    /// *Add Provider*: saves the definition, then keeps it after the others.
    @discardableResult
    public func add(_ definition: ProviderDefinition) throws -> Provider {
        guard provider(id: definition.id) == nil else { throw DefinitionError.duplicateProvider(definition.id) }
        try catalog.add(definition)
        return keep(definition)
    }

    /// *Import*: the reviewed definition, saved and kept like an added one.
    @discardableResult
    public func `import`(_ review: ImportReview) throws -> Provider {
        let definition = try catalog.import(review)
        guard provider(id: definition.id) == nil else { throw DefinitionError.duplicateProvider(definition.id) }
        return keep(definition)
    }

    private func keep(_ definition: ProviderDefinition) -> Provider {
        ProviderFactory.register(custom: definition)
        let provider = make(definition)
        all.append(provider)
        AppLog.providers.info("Kept custom provider \(definition.id)")
        return provider
    }

    // MARK: - Update: the order

    /// Moves a provider, its logins together, `offset` places; stops at either end.
    public func move(_ id: String, by offset: Int) {
        guard offset != 0, let index = all.firstIndex(where: { $0.id == id }) else { return }
        let newIndex = min(max(index + offset, 0), all.count - 1)
        guard newIndex != index else { return }
        all.insert(all.remove(at: index), at: newIndex)
        settings?.setProviderOrder(logins.map(\.id))
    }

    /// The saved order is by login id; a provider goes where its first login
    /// is named, one it doesn't name keeps its place after those it does.
    private static func ordered(_ providers: [Provider], by order: [String]) -> [Provider] {
        guard !order.isEmpty else { return providers }
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        func place(_ provider: Provider, _ offset: Int) -> Int {
            provider.accounts.compactMap { rank[$0.id] }.min() ?? order.count + offset
        }
        return providers.enumerated()
            .sorted { place($0.element, $0.offset) < place($1.element, $1.offset) }
            .map(\.element)
    }

    // MARK: - Delete

    /// Deletes a provider you made: its file, its keys and its place. A
    /// built-in or an extension is never deleted — it is turned off.
    public func remove(_ id: String) throws {
        guard let provider = provider(id: id) else { return }
        guard provider.definition.profile.origin == .custom else { throw DefinitionError.notDeletable(id) }
        try catalog.remove(id)
        for setting in provider.definition.settings where setting.kind == .secret {
            for login in provider.accounts { vault?.delete(setting.id, provider: login.id) }
        }
        ProviderFactory.unregister(custom: id)
        all.removeAll { $0.id == id }
        AppLog.providers.info("Deleted custom provider \(id)")
    }
}
