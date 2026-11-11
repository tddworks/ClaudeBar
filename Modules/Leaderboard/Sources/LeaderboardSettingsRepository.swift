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
    /// What the server took from this device, per provider and day of the
    /// last thirty and two days past them: the day's total as it took it
    /// (design §2a). An earlier day goes again once it reads larger. `nil`
    /// for a record from before this was kept, told apart from an empty one.
    public let sent: [SentDay]?
    /// The days before this one, `yyyy-MM-dd`, go again only when refused:
    /// what the server holds of them is unknown here, after an update from
    /// before `sent`, or under a copied key made its own device.
    public let heldBefore: String?

    public init(username: String, sharing: [String], visible: Bool, lastUpload: Date?,
                sharesCountry: Bool = false, globeHintDismissed: Bool = false, link: ProfileLink? = nil,
                refused: [RefusedDay] = [], shownDevices: [String] = [], machine: String? = nil, addedAsDevice: Bool = false,
                sent: [SentDay]? = nil, heldBefore: String? = nil) {
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
        self.sent = sent?.sorted { ($0.day, $0.provider) < ($1.day, $1.provider) }
        self.heldBefore = heldBefore
    }
}

/// One provider's day as the server took it from this device: its total,
/// the five counts summed. Kept on this device, never sent.
public struct SentDay: Sendable, Equatable, Codable, Hashable {
    public let provider: String
    /// The device's date, `yyyy-MM-dd`, as `DailyTokens.day`.
    public let day: String
    public let total: Int

    public init(provider: String, day: String, total: Int) {
        self.provider = provider
        self.day = day
        self.total = total
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
