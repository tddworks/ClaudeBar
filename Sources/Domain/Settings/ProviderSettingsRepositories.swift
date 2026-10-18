import Quotas
import DataSources
import Foundation
import Mockable
import Providers

/// Claude-specific settings repository, extending base ProviderSettingsRepository.
/// Includes configuration for probe mode (CLI vs API).
/// App uses JSONSettingsRepository (`~/.claudebar/settings.json`).
public protocol ClaudeSettingsRepository: ProviderSettingsRepository {
    /// Gets the probe mode for Claude (CLI or API)
    func claudeProbeMode() -> ClaudeProbeMode

    /// Sets the probe mode for Claude
    func setClaudeProbeMode(_ mode: ClaudeProbeMode)

    /// Whether to fall back to the CLI probe when the OAuth API probe is unavailable.
    /// Defaults to true. Disable to prevent `claude /usage` from running in API mode.
    func claudeCliFallbackEnabled() -> Bool

    /// Sets whether CLI fallback is enabled in API mode
    func setClaudeCliFallbackEnabled(_ enabled: Bool)
}

/// Codex-specific settings repository, extending base ProviderSettingsRepository.
/// Includes configuration for probe mode (RPC vs API).
/// App uses JSONSettingsRepository (`~/.claudebar/settings.json`).
public protocol CodexSettingsRepository: ProviderSettingsRepository {
    /// Gets the probe mode for Codex (RPC or API)
    func codexProbeMode() -> CodexProbeMode

    /// Sets the probe mode for Codex
    func setCodexProbeMode(_ mode: CodexProbeMode)

    /// Whether the Codex CLI session was successfully checked at least once by
    /// an explicit user action (Refresh / Connect). Until this is set, automatic
    /// background refreshes must not run the RPC probe: spawning `codex
    /// app-server` while the CLI is unauthenticated can open the ChatGPT browser
    /// login on its own (issue #216).
    func codexVerifiedAtLeastOnce() -> Bool

    /// Marks (or clears) the verified-at-least-once flag
    func setCodexVerifiedAtLeastOnce(_ verified: Bool)
}

/// DeepSeek-specific settings repository, extending base ProviderSettingsRepository.
/// Stores the API key and env-var name for DeepSeek balance monitoring.
public protocol DeepSeekSettingsRepository: ProviderSettingsRepository {
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


