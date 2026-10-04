import Foundation

/// An amount of money in one currency. Two currencies are never added or compared.
public struct Money: Sendable, Equatable, Hashable {
    public let amount: Decimal
    /// ISO 4217 code — `USD`, `CNY`.
    public let currency: String

    public init(_ amount: Decimal, currency: String = "USD") {
        self.amount = amount
        self.currency = currency
    }
}

/// HOW MUCH IS LEFT — one of two, never both (CANONICAL_MODEL §5).
public enum Left: Sendable, Equatable, Hashable {
    /// "62% left".
    case share(Double)
    /// "$12.40 remaining", "of $50.00". A balance with no ceiling has NO
    /// percentage — writing 100% for it is the lie the status then believes.
    case money(Money, of: Money?)
}

/// WHEN IT REFILLS — the length is the provider's word, never guessed from a
/// quota's name; the Codex RPC's primary window can be the weekly one. A
/// prepaid balance has none.
public struct Window: Sendable, Equatable, Hashable {
    public let length: TimeInterval?
    public let resetsAt: Date?

    public init(length: TimeInterval?, resetsAt: Date?) {
        self.length = length
        self.resetsAt = resetsAt
    }
}
