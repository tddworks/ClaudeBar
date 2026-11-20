import Domain
import Foundation

/// DeepSeek-specific settings repository, extending base ProviderSettingsRepository.
/// Stores the API key and env-var name for DeepSeek balance monitoring.
protocol DeepSeekSettingsRepository {
    /// Gets the environment variable name for DeepSeek API key (empty = use default DEEPSEEK_API_KEY)
    func deepseekAuthEnvVar() -> String

    /// Sets the environment variable name for DeepSeek API key
    func setDeepSeekAuthEnvVar(_ envVar: String)

    /// Saves the DeepSeek API key (for Settings UI input)
    func saveDeepSeekApiKey(_ key: String)

    /// Retrieves the DeepSeek API key
    func getDeepSeekApiKey() -> String?

    /// Deletes the DeepSeek API key
    func deleteDeepSeekApiKey()

    /// Checks if a DeepSeek API key is saved
    func hasDeepSeekApiKey() -> Bool
}


