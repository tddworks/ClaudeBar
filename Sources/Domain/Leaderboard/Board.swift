import Foundation
import Observation

/// "The 7-day Claude board", as this app last read it. Reading it again
/// keeps the last answer until a newer one replaces it, so what the person
/// saw stays on screen. The server ranks; nothing here ranks or counts.
@MainActor
@Observable
public final class Board {
    public let period: BoardPeriod
    /// `nil` = everyone.
    public let provider: String?
    /// The members in rank order, as the server ranked them. `nil` = never
    /// read; empty = no one on it yet.
    public private(set) var members: [Member]?
    /// You on this board, from the same read; `nil` when not ranked on it.
    public private(set) var you: Member?
    /// The last read failed; `members` and `you` are still the last good ones.
    public private(set) var failure: LeaderboardError?

    @ObservationIgnored private let api: any LeaderboardAPI
    @ObservationIgnored private let membership: LeaderboardMembership

    public init(period: BoardPeriod, provider: String? = nil, api: any LeaderboardAPI, membership: LeaderboardMembership) {
        self.period = period
        self.provider = provider
        self.api = api
        self.membership = membership
    }

    /// Reads the board and you on it, together; replaces both only when both
    /// came back. A read cancelled because the person moved on says nothing.
    public func read() async {
        do {
            async let members = api.board(period: period, provider: provider)
            async let summary = membership.summary(period: period, provider: provider)
            let (read, mine) = try await (members, summary)
            self.members = read
            you = mine.onBoard
            failure = nil
        } catch {
            guard !Task.isCancelled else { return }
            failure = error as? LeaderboardError ?? .unreachable
        }
    }
}

extension Board {
    /// A member as a board shows them: their rank, name and link, and their
    /// tokens on this board only. Public, and never the whole member.
    public struct Member: Sendable, Equatable, Codable, Identifiable {
        public let rank: Int
        public let username: String
        public let total: Int
        public let input: Int
        public let output: Int
        public let cache: Int
        /// Tokens per provider, for the mix bar.
        public let byProvider: [String: Int]
        /// The member's profile link, when they added one. Not verified.
        public let link: ProfileLink?

        public var id: String { username }

        public init(rank: Int, username: String, total: Int, input: Int = 0, output: Int = 0, cache: Int = 0,
                    byProvider: [String: Int] = [:], link: ProfileLink? = nil) {
            self.rank = rank
            self.username = username
            self.total = total
            self.input = input
            self.output = output
            self.cache = cache
            self.byProvider = byProvider
            self.link = link
        }

        private enum CodingKeys: String, CodingKey { case rank, username, total, input, output, cache, byProvider, link }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            rank = try c.decode(Int.self, forKey: .rank)
            username = try c.decode(String.self, forKey: .username)
            total = try c.decode(Int.self, forKey: .total)
            input = try c.decodeIfPresent(Int.self, forKey: .input) ?? 0
            output = try c.decodeIfPresent(Int.self, forKey: .output) ?? 0
            cache = try c.decodeIfPresent(Int.self, forKey: .cache) ?? 0
            byProvider = try c.decodeIfPresent([String: Int].self, forKey: .byProvider) ?? [:]
            // A link that doesn't fit its platform's rules is dropped, never shown.
            link = try? c.decodeIfPresent(ProfileLink.self, forKey: .link)
        }
    }
}
