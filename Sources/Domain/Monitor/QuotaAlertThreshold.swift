import Foundation

/// A user-configured quota alert boundary (issue #68).
///
/// The alert fires when a provider's remaining percentage falls below `percent`.
/// Distinct from the fixed healthy/warning/critical/depleted levels on
/// `QuotaStatus`: thresholds are arbitrary user values (35%, 60%, …), several
/// can be active at once, and each is independent of the status colors.
public struct QuotaAlertThreshold: Sendable, Equatable, Hashable, Codable, Comparable, Identifiable {
    /// Remaining-percentage boundary, clamped to 0...100.
    public let percent: Double

    /// Creates a threshold. Values outside 0...100 are clamped, so a stray
    /// settings edit can never produce a threshold that never or always fires.
    public init(percent: Double) {
        self.percent = max(0, min(100, percent))
    }

    public var id: Double { percent }

    /// Human-readable percentage for alert bodies: "35", not "35.0".
    public var displayLabel: String {
        String(format: "%g", percent)
    }

    /// Higher boundary first, so sorting reads most-severe-first.
    public static func > (lhs: QuotaAlertThreshold, rhs: QuotaAlertThreshold) -> Bool {
        lhs.percent > rhs.percent
    }

    public static func < (lhs: QuotaAlertThreshold, rhs: QuotaAlertThreshold) -> Bool {
        lhs.percent < rhs.percent
    }
}
