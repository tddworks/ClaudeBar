import Foundation

/// What is remembered of a membership between launches. The private key is
/// not here: it lives in the `SigningKeyStore`.
public struct LeaderboardRecord: Sendable, Equatable {
    public let username: String
    public let sharing: [String]
    public let visible: Bool
    public let lastUpload: Date?
    public let sharesCountry: Bool
    public let globeHintDismissed: Bool
    public let link: ProfileLink?

    public init(username: String, sharing: [String], visible: Bool, lastUpload: Date?,
                sharesCountry: Bool = false, globeHintDismissed: Bool = false, link: ProfileLink? = nil) {
        self.link = link
        self.username = username
        self.sharing = sharing.sorted()
        self.visible = visible
        self.lastUpload = lastUpload
        self.sharesCountry = sharesCountry
        self.globeHintDismissed = globeHintDismissed
    }
}

/// The leaderboard's settings. A destination's own repository, beside
/// `NotifySettingsRepository`, never under `ProviderSettingsRepository`.
public protocol LeaderboardSettingsRepository: Sendable {
    func leaderboardRecord() -> LeaderboardRecord?
    /// `nil` forgets the membership.
    func saveLeaderboardRecord(_ record: LeaderboardRecord?)
    /// Whether ClaudeBar takes part in the Leaderboard at all. Kept apart
    /// from the record, so it holds before joining and after leaving.
    func isLeaderboardOn() -> Bool
    func setLeaderboardOn(_ on: Bool)
}
