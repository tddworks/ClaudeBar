import Foundation

/// *SHARE MY RANK* — one standing in one board view, as the shared image
/// says it: the rank, where that is on the board, the tokens and the provider
/// mix. Nothing the board doesn't already show, and no other member's name.
public struct RankCard: Sendable, Equatable {
    /// The image's shape, by where it gets posted.
    public enum Shape: String, Sendable, CaseIterable, Identifiable {
        /// X, Instagram and chats.
        case square
        /// The link-card shape, for READMEs and blogs.
        case wide

        public var id: String { rawValue }

        public var pixels: CGSize {
            switch self {
            case .square: CGSize(width: 1080, height: 1080)
            case .wide: CGSize(width: 1200, height: 630)
            }
        }
    }

    /// Where the rank is on the board, in the words the image prints.
    public enum Placement: Sendable, Equatable {
        /// *TOP 24%* — in the top half of every member.
        case top(percent: Int)
        /// *#18 OF 34* — in the bottom half.
        case rank(of: Int)
        /// *TOP 100* — on a board longer than it lists.
        case topHundred
        /// Ranked, but where among how many isn't known.
        case none
    }

    /// One provider's share of the tokens, for the mix bar.
    public struct MixShare: Sendable, Equatable {
        public let provider: String
        public let percent: Int

        public init(provider: String, percent: Int) {
            self.provider = provider
            self.percent = percent
        }
    }

    /// The most members a board lists.
    public static let listLimit = 100

    public let rank: Int
    public let username: String
    public let total: Int
    public let view: BoardView
    /// Largest first; a provider whose share rounds to 0% is left out, as one with no tokens is.
    public let mix: [MixShare]
    /// Every member in the view, when the board lists them all and the rank is among them.
    public let members: Int?
    public let placement: Placement

    /// `nil` until there's a rank to share: before the first upload, or with
    /// no tokens in this view.
    public init?(standing: Standing?, in view: BoardView, board: [Standing]) {
        guard let standing, standing.total > 0 else { return nil }
        rank = standing.rank
        username = standing.username
        total = standing.total
        self.view = view

        let sum = Double(standing.byProvider.values.reduce(0, +))
        mix = standing.byProvider
            .filter { $0.value > 0 }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { MixShare(provider: $0.key, percent: Int((Double($0.value) / sum * 100).rounded())) }
            .filter { $0.percent > 0 }

        let listsEveryone = board.count < Self.listLimit
        members = listsEveryone && standing.rank <= board.count ? board.count : nil
        if let members {
            placement = standing.rank * 2 <= members
                ? .top(percent: Int((Double(standing.rank) / Double(members) * 100).rounded(.up)))
                : .rank(of: members)
        } else if !listsEveryone && standing.rank <= Self.listLimit {
            placement = .topHundred
        } else {
            placement = .none
        }
    }
}
