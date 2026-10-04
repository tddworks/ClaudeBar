import Foundation

/// *USERNAME* — the name on the board, chosen at join and shown publicly.
/// An invalid name can't be held at all; whether it is free is the server's
/// to answer. The rule is pinned by `Tests/DomainTests/Leaderboard/vectors.json`,
/// which the Worker checks too.
public struct Username: Sendable, Hashable, CustomStringConvertible {
    public let value: String

    public init?(_ text: String) {
        guard (3...20).contains(text.count),
              text.unicodeScalars.allSatisfy({ Self.allowed.contains($0) }) else { return nil }
        value = text
    }

    public var description: String { "@" + value }

    private static let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
}
