import Foundation

/// What is remembered of a membership between launches. The private key is
/// not here: it lives in the `SigningKeyStore`.
public struct LeaderboardRecord: Sendable, Equatable {
    public let username: String
    public let sharing: [String]
    public let visible: Bool
    public let lastUpload: Date?

    public init(username: String, sharing: [String], visible: Bool, lastUpload: Date?) {
        self.username = username
        self.sharing = sharing.sorted()
        self.visible = visible
        self.lastUpload = lastUpload
    }
}

/// The leaderboard's settings. A destination's own repository, beside
/// `NotifySettingsRepository`, never under `ProviderSettingsRepository`.
public protocol LeaderboardSettingsRepository: Sendable {
    func leaderboardRecord() -> LeaderboardRecord?
    /// `nil` forgets the membership.
    func saveLeaderboardRecord(_ record: LeaderboardRecord?)
}
