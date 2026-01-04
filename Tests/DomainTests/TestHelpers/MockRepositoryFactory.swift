import Foundation
import Mockable
@testable import Domain

/// Shared test helper factory for creating mock repositories
/// Eliminates duplication across provider tests (CopilotProvider, ZaiProvider, etc.)
struct MockRepositoryFactory {
    
    /// Creates a mock settings repository for provider tests
    /// - Parameter enabled: Whether the provider is enabled (defaults to true)
    /// - Returns: A configured MockProviderSettingsRepository
    static func makeSettingsRepository(enabled: Bool = true) -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(enabled)
        given(mock).isEnabled(forProvider: .any).willReturn(enabled)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        return mock
    }
    
    /// Creates a mock credential repository for provider tests
    /// - Parameter username: The username to return (empty string = nil)
    /// - Parameter hasToken: Whether the token exists
    /// - Returns: A configured MockCredentialRepository
    static func makeCredentialRepository(username: String = "", hasToken: Bool = false) -> MockCredentialRepository {
        let mock = MockCredentialRepository()
        given(mock).get(forKey: .any).willReturn(username.isEmpty ? nil : username)
        given(mock).exists(forKey: .any).willReturn(hasToken)
        given(mock).save(.any, forKey: .any).willReturn()
        given(mock).delete(forKey: .any).willReturn()
        return mock
    }
    
    /// Creates a mock config repository for provider tests
    /// - Parameter zaiConfigPath: The Z.ai config path to return
    /// - Parameter glmAuthEnvVar: The GLM auth env var to return
    /// - Parameter copilotAuthEnvVar: The Copilot auth env var to return
    /// - Returns: A configured MockProviderConfigRepository
    static func makeConfigRepository(
        zaiConfigPath: String = "",
        glmAuthEnvVar: String = "",
        copilotAuthEnvVar: String = ""
    ) -> MockProviderConfigRepository {
        let mock = MockProviderConfigRepository()
        given(mock).zaiConfigPath().willReturn(zaiConfigPath)
        given(mock).glmAuthEnvVar().willReturn(glmAuthEnvVar)
        given(mock).copilotAuthEnvVar().willReturn(copilotAuthEnvVar)
        given(mock).setZaiConfigPath(.any).willReturn()
        given(mock).setGlmAuthEnvVar(.any).willReturn()
        given(mock).setCopilotAuthEnvVar(.any).willReturn()
        return mock
    }
}
