import Foundation
import ClaudeBarKit

extension Money {
    /// An amount in one currency.
    public convenience init(_ amount: Decimal, currency: String = "USD") {
        self.init(amountNanos: amount.nanos, currency: currency)
    }

    public var amount: Decimal { Decimal(nanos: amountNanos) }

    public static func == (lhs: Money, rhs: Money) -> Bool { lhs.isEqual(rhs) }
}

extension Left {
    /// "62% left".
    public static func share(_ percent: Double) -> Left { Left.Share(percent: percent) }
    /// "$12.40 remaining", "of $50.00".
    public static func money(_ remaining: Money, of ceiling: Money?) -> Left {
        Left.Balance(remaining: remaining, ceiling: ceiling)
    }

    public static func == (lhs: Left, rhs: Left) -> Bool { lhs.isEqual(rhs) }

    /// How much is left, to `switch` on.
    public enum Shape: Equatable, Sendable {
        case share(Double)
        case money(Money, of: Money?)
    }

    public var shape: Shape {
        switch onEnum(of: self) {
        case .share(let share): .share(share.percent)
        case .balance(let balance): .money(balance.remaining, of: balance.ceiling)
        }
    }
}

extension Window {
    public convenience init(length: TimeInterval?, resetsAt: Date?) {
        self.init(lengthSeconds: length.kotlin, resetsAtSeconds: resetsAt.map(\.kernelSeconds).kotlin)
    }

    public var length: TimeInterval? { lengthSeconds.swift }
    public var resetsAt: Date? { resetsAtSeconds.swift.map(Date.init(kernelSeconds:)) }

    public static func == (lhs: Window, rhs: Window) -> Bool { lhs.isEqual(rhs) }
}
