import Foundation
import Mockable

/// Repository protocol for AI providers.
/// Defines the interface for managing a collection of providers.
///
/// `@MainActor`-isolated because its members vend/inspect `any AIProvider` (now
/// main-actor-isolated): `enabled` reads each provider's `isEnabled`, `provider(id:)`
/// reads `id`. The sole conformer (`AIProviders`) and sole holder (`QuotaMonitor`) are
/// both already main-isolated.
@Mockable
@MainActor
public protocol AIProviderRepository: AnyObject, Sendable {
    /// All registered providers
    var all: [any AIProvider] { get }

    /// Only enabled providers (filtered by isEnabled state)
    var enabled: [any AIProvider] { get }

    /// Finds a provider by its ID
    func provider(id: String) -> (any AIProvider)?

    /// Adds a provider if not already present
    func add(_ provider: any AIProvider)

    /// Removes a provider by ID
    func remove(id: String)
}
