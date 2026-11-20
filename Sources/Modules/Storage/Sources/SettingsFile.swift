import Foundation
import Providers
import Monitoring
import Leaderboard
import Activity
import Alerting
import LocalAPI

/// Every module's settings, kept in the one `~/.claudebar/settings.json`:
/// the providers and their logins, hooks, the local API, Notify!, webhooks,
/// quota alerts, recaps, the leaderboard and Rest when empty. Each module asks
/// through its own port; this is the one thing that answers them all.
public protocol SettingsFile:
    MultiAccountSettingsRepository,
    HookSettingsRepository,
    LocalAPISettingsRepository,
    NotifySettingsRepository,
    QuotaAlertSettingsRepository,
    WebhookSettingsRepository,
    RecapSentRepository,
    LeaderboardSettingsRepository,
    RestWhenEmptyRepository,
    Sendable
{
    /// The destinations' secrets (Notify!'s token, the webhooks' URLs), in the
    /// Keychain, or its fallback when the Keychain refuses this build.
    var destinationSecrets: any DestinationSecrets { get }
}
