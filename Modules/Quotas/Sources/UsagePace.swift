import Foundation

/// Represents the pace of quota consumption relative to expected usage over time.
///
/// - `.onPace`: Usage within `SpendRate.margin` (5 points) of the time gone: it lasts until the reset
/// - `.ahead`: More than 5 points ahead: it runs out before the reset
/// - `.behind`: More than 5 points behind (room to spare)
/// - `.unknown`: No `SpendRate` (no window, or under its noise floor)
///
/// - Note: Interim — today's shape, moved unchanged into the kernel.
///   Final version (docs/architecture/CANONICAL_MODEL.md) — becomes `Pace`: exists only inside a `Window` with a reset, `unknown`
///   otherwise, never `onPace` (§5).
public enum UsagePace: Sendable, Equatable {
    case onPace
    case ahead
    case behind
    case unknown

    // MARK: - Factory Methods

    /// Creates a pace from usage against the time gone, `unknown` when they
    /// make no `SpendRate` (before its noise floor, or once the window is over).
    /// - Parameters:
    ///   - percentUsed: How much quota has been consumed (0-100+)
    ///   - percentTimeElapsed: How much of the reset period has elapsed (0-100)
    /// - Returns: The pace classification
    public static func from(percentUsed: Double, percentTimeElapsed: Double) -> UsagePace {
        SpendRate(percentUsed: percentUsed, percentTimeElapsed: percentTimeElapsed).map(UsagePace.init(rate:)) ?? .unknown
    }

    /// The pace a rate reads: *Running hot* exactly when it runs out before
    /// the reset — the same rule `Forecast` reads — *Room to spare* when it
    /// has room to spare, *On track* within the margin between.
    public init(rate: SpendRate) {
        if rate.runsOutBeforeReset {
            self = .ahead
        } else if rate.hasRoomToSpare {
            self = .behind
        } else {
            self = .onPace
        }
    }

    // MARK: - Display

    /// Human-readable name for this pace
    public var displayName: String {
        switch self {
        case .onPace: "On track"
        case .ahead: "Running hot"
        case .behind: "Room to spare"
        case .unknown: "Unknown"
        }
    }

    /// SF Symbol name representing this pace
    public var symbolName: String {
        switch self {
        case .onPace: "equal.circle.fill"
        case .ahead: "hare.fill"
        case .behind: "tortoise.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }
}
