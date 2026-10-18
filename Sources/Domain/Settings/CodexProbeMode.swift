import Quotas
import DataSources
import Providers
import Foundation

/// Codex's data source, as the Codex card names it — the `kind` of one of
/// the data sources in `codex.json`, saved as `codex.probeMode`.
/// Users can switch between RPC (default) and API modes in Settings.
public enum CodexProbeMode: String, Sendable, Equatable, CaseIterable {
    /// Use the Codex RPC client (`codex app-server`) to fetch usage data.
    /// This is the default mode and works via JSON-RPC over stdin/stdout.
    case rpc

    /// Use the ChatGPT backend API to fetch usage data directly.
    /// Requires valid OAuth credentials in ~/.codex/auth.json.
    /// Faster than RPC mode as it doesn't spawn a subprocess.
    case api
}
