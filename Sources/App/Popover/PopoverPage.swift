import Foundation

/// What the popover shows under its pills: *All*, the *Leaderboard*, or one
/// provider — which one is `QuotaMonitor.selectedProviderId`.
public enum PopoverPage: Equatable, Sendable {
    case all
    case leaderboard
    case provider

    /// The page that can be shown: All needs two providers, the Leaderboard
    /// needs to be on; otherwise the provider.
    public func shown(allOffered: Bool, leaderboardOn: Bool) -> PopoverPage {
        switch self {
        case .all: allOffered ? .all : .provider
        case .leaderboard: leaderboardOn ? .leaderboard : .provider
        case .provider: .provider
        }
    }
}
