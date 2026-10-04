import Foundation

/// Represents the pace of quota consumption relative to expected usage over time.
///
/// - `.onPace`: Usage is roughly matching expected pace (within 5% threshold)
/// - `.ahead`: Consuming faster than expected (warning: may run out early)
/// - `.behind`: Consuming slower than expected (room to spare)
/// - `.unknown`: Cannot determine pace (no reset time available)
///
/// - Note: Interim — today's shape, moved unchanged into the kernel.
///   Final version (docs/architecture/CANONICAL_MODEL.md) — becomes `Pace`: exists only inside a `Window` with a reset, `unknown`
///   otherwise, never `onPace` (§5).
public enum UsagePace: Sendable, Equatable {
    case onPace
    case ahead
    case behind
    case unknown

    /// The threshold (in percentage points) within which usage is considered "on pace".
    private static let onPaceThreshold: Double = 5.0

    // MARK: - Factory Methods

    /// Creates a pace from the difference between actual usage and expected usage.
    /// - Parameters:
    ///   - percentUsed: How much quota has been consumed (0-100+)
    ///   - percentTimeElapsed: How much of the reset period has elapsed (0-100)
    /// - Returns: The pace classification
    public static func from(percentUsed: Double, percentTimeElapsed: Double) -> UsagePace {
        let difference = percentUsed - percentTimeElapsed
        if abs(difference) <= onPaceThreshold {
            return .onPace
        } else if difference > 0 {
            return .ahead
        } else {
            return .behind
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
