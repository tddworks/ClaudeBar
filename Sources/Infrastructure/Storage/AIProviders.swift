import Foundation
import Combine
import Domain

/// Repository of AI providers.
/// ObservableObject class that provides access to all providers and filters by enabled state.
public final class AIProviders: ObservableObject, AIProviderRepository, @unchecked Sendable {
    public let objectWillChange = ObservableObjectPublisher()

    // MARK: - All Providers

    /// All registered providers
    @Published public private(set) var all: [any AIProvider]

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
        objectWillChange.send()
    }

    /// Removes a provider by ID
    /// - Parameter id: The provider identifier to remove
    public func remove(id: String) {
        all.removeAll { $0.id == id }
        objectWillChange.send()
    }
}
