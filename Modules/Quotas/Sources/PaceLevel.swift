import Foundation

/// Six-level urgency for the expected-pace tick, graded by the quota's
/// `SpendRate` (the projected end-of-period usage). Separate from `QuotaStatus`,
/// which colors the bar itself.
public enum PaceLevel: Int, Sendable, Comparable, CaseIterable {
    case comfortable = 0 // projected under 50%
    case onTrack = 1     // projected 50-75%
    case warming = 2     // projected 75-90%
    case pressing = 3    // projected 90-100%
    case critical = 4    // projected 100-120%
    case runaway = 5     // projected 120%+

    public static func < (lhs: PaceLevel, rhs: PaceLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The level for this usage, or nil when it has no `SpendRate` (before
    /// its noise floor, or once the window is over).
    /// - Parameters:
    ///   - percentUsed: How much quota has been consumed (0-100)
    ///   - percentTimeElapsed: How much of the reset period has elapsed (0-100)
    public static func from(percentUsed: Double, percentTimeElapsed: Double) -> PaceLevel? {
        SpendRate(percentUsed: percentUsed, percentTimeElapsed: percentTimeElapsed).map(PaceLevel.init(rate:))
    }

    /// The level a rate grades to.
    public init(rate: SpendRate) {
        switch rate.value {
        case ..<0.50: self = .comfortable
        case 0.50..<0.75: self = .onTrack
        case 0.75..<0.90: self = .warming
        case 0.90..<1.00: self = .pressing
        case 1.00..<1.20: self = .critical
        default: self = .runaway
        }
    }
}

extension UsageQuota {
    /// The pace level for the expected-pace tick, or nil when it cannot be graded.
    public var paceLevel: PaceLevel? {
        rate.map(PaceLevel.init(rate:))
    }
}
