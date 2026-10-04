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
/// shown, whether your country is on the globe, and every day you uploaded.
public struct MemberSummary: Sendable, Equatable, Codable {
    public let standing: Standing?
    public let days: [DailyTokens]
    public let visible: Bool
    public let sharesCountry: Bool
    /// The country the server keeps for the globe, when you opted in.
    public let country: String?

    public init(standing: Standing?, days: [DailyTokens], visible: Bool, sharesCountry: Bool = false, country: String? = nil) {
        self.standing = standing
        self.days = days
        self.visible = visible
        self.sharesCountry = sharesCountry
        self.country = country
    }

    private enum CodingKeys: String, CodingKey {
        case standing, days, visible, country
        case sharesCountry = "shareCountry"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        standing = try container.decodeIfPresent(Standing.self, forKey: .standing)
        days = try container.decode([DailyTokens].self, forKey: .days)
        visible = try container.decode(Bool.self, forKey: .visible)
        sharesCountry = try container.decodeIfPresent(Bool.self, forKey: .sharesCountry) ?? false
        country = try container.decodeIfPresent(String.self, forKey: .country)
    }
}

/// A change to your membership on the server; fields left `nil` stay as they are.
public struct MemberChange: Sendable, Equatable, Encodable {
    public let username: String?
    public let visible: Bool?
    public let sharesCountry: Bool?

    public init(username: String? = nil, visible: Bool? = nil, sharesCountry: Bool? = nil) {
        self.username = username
        self.visible = visible
        self.sharesCountry = sharesCountry
    }

    private enum CodingKeys: String, CodingKey {
        case username, visible
        case sharesCountry = "shareCountry"
    }
}

/// *WHERE CLAUDEBAR IS USED* — opted-in members per country, only where at
/// least three are; the rest are counted, never named.
public struct GlobeSummary: Sendable, Equatable, Decodable {
    public struct Country: Sendable, Equatable, Decodable {
        public let country: String
        public let members: Int
        public let tokens: Int

        public init(country: String, members: Int, tokens: Int) {
            self.country = country
            self.members = members
            self.tokens = tokens
        }
    }

    public let countries: [Country]
    public let hiddenCountries: Int

    public init(countries: [Country], hiddenCountries: Int) {
        self.countries = countries
        self.hiddenCountries = hiddenCountries
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
    func update(_ change: MemberChange, as credentials: MemberCredentials) async throws
    func leave(as credentials: MemberCredentials) async throws
    func board(in view: BoardView) async throws -> [Standing]
    func globe(in view: BoardView) async throws -> GlobeSummary
}
