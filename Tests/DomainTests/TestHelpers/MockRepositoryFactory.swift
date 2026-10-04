import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

/// Shared test helper factory for creating mock/test repositories
/// Eliminates duplication across provider tests (stub providers)
struct MockRepositoryFactory {

    /// Creates a mock settings repository for provider tests (base ProviderSettingsRepository)
    /// - Parameter enabled: Whether the provider is enabled (defaults to true)
    /// - Returns: A configured MockProviderSettingsRepository
    static func makeSettingsRepository(enabled: Bool = true) -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(enabled)
        given(mock).isEnabled(forProvider: .any).willReturn(enabled)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        given(mock).customCardURL(forProvider: .any).willReturn(nil)
        given(mock).setCustomCardURL(.any, forProvider: .any).willReturn()
        return mock
    }
}
