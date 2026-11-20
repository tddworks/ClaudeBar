import Quotas
import DataSources
import Providers
import Foundation
import Mockable

/// Protocol for storing and retrieving credentials.
/// Allows different implementations (UserDefaults, Keychain, etc.) and easy testing.
@Mockable
protocol CredentialRepository: Sendable {
    /// Saves a credential value for the given key.
    func save(_ value: String, forKey key: String)

    /// Retrieves a credential value for the given key.
    func get(forKey key: String) -> String?

    /// Deletes the credential for the given key.
    /// - Returns: `true` when the credential is absent after the operation.
    @discardableResult
    func delete(forKey key: String) -> Bool

    /// Checks if a credential exists for the given key.
    func exists(forKey key: String) -> Bool
}

/// Well-known credential keys
enum CredentialKey {
    static let githubToken = "github-copilot-token"
    static let githubUsername = "github-username"
    static let vercelApiKey = "vercel-ai-gateway-api-key"
    static let zaiApiKey = "zai-glm-api-key"
    static let notifyDeviceToken = "notify-device-token"
}
