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
    /// Days the server refused, to send again.
    public let refused: [RefusedDay]
    /// The keys of the devices already shown as added, each shown once.
    /// This device's own, never sent.
    public let shownDevices: [String]
    /// Which machine made the key: a hash of its hardware UUID, salted with
    /// the key's public half, never the UUID itself, and never sent. `nil`
    /// for a key from before this was kept, or made where the UUID can't be
    /// read. A launch on another machine finds a copied key by it (design §2a).
    public let machine: String?
    /// The key was added as a device of the member (through a code, or by
    /// *Make this Mac its own device*), not the one that joined, so it is
    /// held to a first week. `/me` can't say: an added device in its first
    /// week sees only itself, as a member with one device does.
    public let addedAsDevice: Bool

    public init(username: String, sharing: [String], visible: Bool, lastUpload: Date?,
                sharesCountry: Bool = false, globeHintDismissed: Bool = false, link: ProfileLink? = nil,
                refused: [RefusedDay] = [], shownDevices: [String] = [], machine: String? = nil, addedAsDevice: Bool = false) {
        self.link = link
        self.username = username
        self.sharing = sharing.sorted()
        self.visible = visible
        self.lastUpload = lastUpload
        self.sharesCountry = sharesCountry
        self.globeHintDismissed = globeHintDismissed
        self.refused = refused
        self.shownDevices = shownDevices.sorted()
        self.machine = machine
        self.addedAsDevice = addedAsDevice
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
