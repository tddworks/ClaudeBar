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


/// What the server holds about you: your name, you on the board asked for,
/// whether you're shown, whether your country is on the globe, and every day
/// you uploaded.
public struct MemberSummary: Sendable, Equatable, Codable {
    /// The member's name on the server, which another device may have changed.
    /// `nil` from a server that doesn't say it.
    public let username: String?
    /// You as that board shows you; `nil` when not ranked on it.
    public let onBoard: Board.Member?
    public let days: [DailyTokens]
    public let visible: Bool
    public let sharesCountry: Bool
    /// The country the server keeps for the globe, when you opted in.
    public let country: String?
    public let link: ProfileLink?
    /// Whether the answer said where the member stands on the globe, and
    /// whether it said what their link is (a `null` link says there is none).
    /// A device follows only what the server said.
    let reportsSharesCountry: Bool
    let reportsLink: Bool

    public init(username: String? = nil, onBoard: Board.Member?, days: [DailyTokens], visible: Bool, sharesCountry: Bool = false,
                country: String? = nil, link: ProfileLink? = nil) {
        self.username = username
        self.onBoard = onBoard
        self.days = days
        self.visible = visible
        self.sharesCountry = sharesCountry
        self.country = country
        self.link = link
        reportsSharesCountry = true
        reportsLink = true
    }

    private enum CodingKeys: String, CodingKey {
        case username, days, visible, country, link
        case onBoard = "standing"
        case sharesCountry = "shareCountry"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        onBoard = try container.decodeIfPresent(Board.Member.self, forKey: .onBoard)
        days = try container.decode([DailyTokens].self, forKey: .days)
        visible = try container.decode(Bool.self, forKey: .visible)
        sharesCountry = try container.decodeIfPresent(Bool.self, forKey: .sharesCountry) ?? false
        country = try container.decodeIfPresent(String.self, forKey: .country)
        link = try? container.decodeIfPresent(ProfileLink.self, forKey: .link)
        reportsSharesCountry = container.contains(.sharesCountry)
        // A link that doesn't fit its platform's rules is dropped, and not taken as "no link".
        reportsLink = container.contains(.link) && (link != nil || (try? container.decodeNil(forKey: .link)) == true)
    }
}

/// A day the server refused, alone: the rest of the upload was kept.
/// `PUT /usage` lists these under `refused` in a `2xx`.
public struct RefusedDay: Sendable, Equatable, Codable, Hashable {
    public let provider: String
    /// The device's date, `yyyy-MM-dd`, as `DailyTokens.day`.
    public let day: String
    /// `future`, `tooOld` or `cap`; another reason is kept as the server said it.
    public let reason: String

    public init(provider: String, day: String, reason: String) {
        self.provider = provider
        self.day = day
        self.reason = reason
    }

    /// Why, in the person's words.
    public var why: String {
        switch reason {
        case "future": "it is in the future by the server's clock"
        case "tooOld": "it is more than 30 days old"
        case "cap": "it would put your total for the day over the daily cap"
        default: "the leaderboard refused it (\(reason))"
        }
    }
}

/// A change to your membership on the server; fields left `nil` stay as they are.
public struct MemberChange: Sendable, Equatable, Encodable {
    /// A profile link to set, or to remove — distinct from leaving it as it is.
    public enum LinkChange: Sendable, Equatable {
        case set(ProfileLink)
        case remove
    }

    public let username: String?
    public let visible: Bool?
    public let sharesCountry: Bool?
    public let link: LinkChange?

    public init(username: String? = nil, visible: Bool? = nil, sharesCountry: Bool? = nil, link: LinkChange? = nil) {
        self.username = username
        self.visible = visible
        self.sharesCountry = sharesCountry
        self.link = link
    }

    private enum CodingKeys: String, CodingKey {
        case username, visible, link
        case sharesCountry = "shareCountry"
    }

    /// Fields left `nil` are left out; removing the link is an explicit `"link": null`.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(username, forKey: .username)
        try container.encodeIfPresent(visible, forKey: .visible)
        try container.encodeIfPresent(sharesCountry, forKey: .sharesCountry)
        switch link {
        case .set(let link): try container.encode(link, forKey: .link)
        case .remove: try container.encodeNil(forKey: .link)
        case nil: break
        }
    }
}

/// *WHERE CLAUDEBAR IS USED* — every country opted-in members share. Members
/// and tokens only where at least three are (`countries`); the rest are named
/// without a number (`present`), so no number is one person's own.
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
    public let present: [String]

    public init(countries: [Country], present: [String]) {
        self.countries = countries
        self.present = present
    }

    /// Every country on the globe, with numbers or without.
    public var countryCount: Int { countries.count + present.count }

    private enum CodingKeys: String, CodingKey { case countries, present }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        countries = try container.decode([Country].self, forKey: .countries)
        // A server from before named countries sends none.
        present = try container.decodeIfPresent([String].self, forKey: .present) ?? []
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
    /// Sends days; answers the ones the server refused, each alone. A server
    /// from before devices refuses none this way: it fails the whole upload.
    func upload(_ days: [DailyTokens], as credentials: MemberCredentials) async throws -> [RefusedDay]
    /// You on one board, with your name and settings. `provider` `nil` = everyone.
    func me(period: BoardPeriod, provider: String?, as credentials: MemberCredentials) async throws -> MemberSummary
    func update(_ change: MemberChange, as credentials: MemberCredentials) async throws
    func leave(as credentials: MemberCredentials) async throws
    /// One board's members, in rank order. `provider` `nil` = everyone.
    func board(period: BoardPeriod, provider: String?) async throws -> [Board.Member]
    func globe(period: BoardPeriod) async throws -> GlobeSummary
}
