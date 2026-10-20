import Foundation

/// How the tile's row of quota windows is arranged.
///
/// The row is the one thing on a Lock Screen that a person learns by heart, so
/// how it is arranged is their choice rather than ClaudeBar's. Both orders
/// keep the same headline: the tile's colour, its bar and its countdown still
/// come from the worst quota, so the number that needs attention is the one
/// the tile is about whichever order the row is in.
public enum NotifyTileOrder: String, Sendable, Equatable, CaseIterable {
    /// The worst quota leads, and the row moves as the quotas move.
    ///
    /// The row is a ranking of now: a quota that falls below its neighbour
    /// moves past it. Good for finding the quota that needs attention, poor
    /// for finding the quota that is always in the same place.
    case worstFirst

    /// Each provider's windows sit together, and a quota moving moves nothing.
    ///
    /// Providers in name order, and within a provider the short-term window
    /// before the weekly one, so the eye can pair a provider's two quotas
    /// without reading every label.
    case fixed
}
