import Foundation

/// Represents the pace of quota consumption relative to expected usage over time.
///
/// - `.onPace`: Usage trails the time gone by at most 5 points: it lasts until the reset
/// - `.ahead`: Consuming faster than the window passes: it runs out before the reset
/// - `.behind`: Consuming slower than expected (room to spare)
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

    /// How far (in percentage points) usage can trail the time gone and still
    /// be *On track*.
    private static let onPaceThreshold: Double = 5.0

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

    /// The pace a rate reads: *Running hot* whenever it runs out before the
    /// window refills (rate above 1) — the same law as `Forecast` — *On track*
    /// up to 5 points under the time gone, *Room to spare* below that.
    public init(rate: SpendRate) {
        if !rate.outlastsWindow {
            self = .ahead
        } else if rate.percentTimeElapsed - rate.percentUsed <= Self.onPaceThreshold {
            self = .onPace
        } else {
            self = .behind
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
