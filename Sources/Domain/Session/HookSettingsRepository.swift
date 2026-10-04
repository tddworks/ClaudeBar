import Quotas
import DataSources
import Providers
import Foundation

/// Constants for hook configuration
public enum HookConstants {
    /// Default port for the hook HTTP server
    public static let defaultPort: UInt16 = 19847

    /// Environment variable ClaudeBar sets on the claude sessions it spawns
    /// itself (quota probes). The hook command ClaudeBar installs checks it
    /// and exits without POSTing, so a background quota poll can't loop back
    /// through the user's hooks as a Claude session (#222).
    public static let probeEnvironmentKey = "CLAUDEBAR_PROBE"
}

/// Settings repository for hook configuration.
/// Standalone protocol (not extending ProviderSettingsRepository) since hooks aren't a provider.
public protocol HookSettingsRepository: Sendable {
    /// Whether hooks are enabled
    func isHookEnabled() -> Bool

    /// Sets whether hooks are enabled
    func setHookEnabled(_ enabled: Bool)

    /// The port number for the hook HTTP server (0 = auto-assign)
    func hookPort() -> Int

    /// Sets the port number for the hook HTTP server
    func setHookPort(_ port: Int)
}
