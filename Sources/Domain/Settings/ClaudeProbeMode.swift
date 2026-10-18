import Quotas
import DataSources
import Providers
import Foundation

/// Claude's data source, as the Claude card names it — the `kind` of one of
/// the data sources in `claude.json`, saved as `claude.probeMode`.
/// Users can switch between CLI (default) and API modes in Settings.
public enum ClaudeProbeMode: String, Sendable, Equatable, CaseIterable {
    /// Use the Claude CLI (`claude /usage`) to fetch usage data.
    /// This is the default mode and works without additional configuration.
    case cli

    /// Use the Claude OAuth API to fetch usage data directly.
    /// Requires valid OAuth credentials in ~/.claude/.credentials.json or Keychain.
    /// Faster than CLI mode as it doesn't spawn a subprocess.
    case api
}
