import Foundation
import Observation
import Mockable

/// Repository protocol for AI providers.
/// Defines the interface for managing a collection of providers.
@Mockable
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

/// Repository of AI providers.
/// Rich domain model that provides access to all providers and filters by enabled state.
@Observable
public final class AIProviders: AIProviderRepository, @unchecked Sendable {
    // MARK: - All Providers

    /// All registered providers
    public private(set) var all: [any AIProvider]

    // MARK: - Filtered Views

    /// Only enabled providers (computed from all providers' isEnabled state)
    public var enabled: [any AIProvider] {
        all.filter { $0.isEnabled }
    }

    // MARK: - Initialization

    /// Creates an AIProviders repository with the given providers
    /// - Parameter providers: The providers to manage
    public init(providers: [any AIProvider]) {
        self.all = providers
    }

    // MARK: - Lookup

    /// Finds a provider by its ID
    /// - Parameter id: The provider identifier (e.g., "claude", "codex", "gemini")
    /// - Returns: The provider if found, nil otherwise
    public func provider(id: String) -> (any AIProvider)? {
        all.first { $0.id == id }
    }

    // MARK: - Dynamic Provider Management

    /// Adds a provider if not already present
    /// - Parameter provider: The provider to add
    public func add(_ provider: any AIProvider) {
        guard !all.contains(where: { $0.id == provider.id }) else {
            return
        }
        all.append(provider)
    }

    /// Removes a provider by ID
    /// - Parameter id: The provider identifier to remove
    public func remove(id: String) {
        all.removeAll { $0.id == id }
    }
}
