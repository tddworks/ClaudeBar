import Foundation
import Mockable

/// *TODAY · 7 DAYS · 30 DAYS* — the periods a board can be read over. Closed.
public enum BoardPeriod: String, Sendable, CaseIterable, Codable {
    case today
    case sevenDays = "7d"
    case thirtyDays = "30d"

    public var label: String {
        switch self {
        case .today: "Today"
        case .sevenDays: "7 days"
        case .thirtyDays: "30 days"
        }
    }
}

/// A period and, optionally, one provider: `7 days · Claude`. A rank only
/// means something within one view.
public struct BoardView: Sendable, Hashable {
    public let period: BoardPeriod
    /// `nil` is every provider.
    public let provider: String?

    public init(period: BoardPeriod, provider: String? = nil) {
        self.period = period
        self.provider = provider
    }
}

/// One member's place in one board view.
public struct Standing: Sendable, Equatable, Codable, Identifiable {
    public let rank: Int
    public let username: String
    public let total: Int
    public let input: Int
    public let output: Int
    public let cache: Int
    /// Tokens per provider, for the mix bar.
    public let byProvider: [String: Int]

    public var id: String { username }

    public init(rank: Int, username: String, total: Int, input: Int = 0, output: Int = 0, cache: Int = 0,
                byProvider: [String: Int] = [:]) {
        self.rank = rank
        self.username = username
        self.total = total
        self.input = input
        self.output = output
        self.cache = cache
        self.byProvider = byProvider
    }
}

/// What the server holds about you: your standing in a view, whether you're
/// shown, and every day you uploaded.
public struct MemberSummary: Sendable, Equatable, Codable {
    public let standing: Standing?
    public let days: [DailyTokens]
    public let visible: Bool

    public init(standing: Standing?, days: [DailyTokens], visible: Bool) {
        self.standing = standing
        self.days = days
        self.visible = visible
    }
}

/// Who signs a request: the name and the key only this Mac holds.
public struct MemberCredentials: Sendable {
    public let username: Username
    public let key: SigningKey

    public init(username: Username, key: SigningKey) {
        self.username = username
        self.key = key
    }
}

public enum LeaderboardError: Error, Sendable, Equatable, LocalizedError {
    case usernameTaken
    case notShareable(String)
    case nothingShared
    case notJoined
    /// The server refused the signature: the key no longer matches the name.
    case unauthorized
    case rejected(String)
    case unreachable

    public var errorDescription: String? {
        switch self {
        case .usernameTaken: "That username is taken. Try another."
        case .notShareable(let provider): "\(provider) has no token logs on this Mac, so it can't be shared."
        case .nothingShared: "Pick at least one provider to share."
        case .notJoined: "You haven't joined the leaderboard."
        case .unauthorized: "The leaderboard didn't accept this Mac's key for your username."
        case .rejected(let reason): reason
        case .unreachable: "The leaderboard can't be reached right now."
        }
    }
}

/// The leaderboard server. Every call but `join` and `board` is signed.
@Mockable
public protocol LeaderboardAPI: Sendable {
    func join(username: String, publicKey: String) async throws
    func upload(_ days: [DailyTokens], as credentials: MemberCredentials) async throws
    func me(in view: BoardView, as credentials: MemberCredentials) async throws -> MemberSummary
    func update(username: String?, visible: Bool?, as credentials: MemberCredentials) async throws
    func leave(as credentials: MemberCredentials) async throws
    func board(in view: BoardView) async throws -> [Standing]
}
