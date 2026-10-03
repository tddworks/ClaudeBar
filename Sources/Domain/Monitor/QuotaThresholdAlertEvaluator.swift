import Foundation

/// Evaluates a provider's remaining percentage against the user's configured
/// alert thresholds (issue #68), with hysteresis: each threshold fires once per
/// crossing, does not refire while the percentage stays below it, and re-arms
/// once the percentage recovers above it — so a sustained breach produces one
/// notification, not one per refresh.
///
/// A small recovery margin keeps the boundary from flapping: hovering a
/// fraction above the threshold does not re-arm it. A provider must climb at
/// least `recoveryMargin` percentage points clear before the same threshold can
/// fire again.
///
/// A struct on purpose: the crossing state is mutable value state owned by the
/// caller (`QuotaMonitor`, which is `@MainActor`), so there is no shared mutable
/// state to protect.
public struct QuotaThresholdAlertEvaluator: Sendable {
    /// Percentage points a provider must recover above a threshold before that
    /// threshold can fire again.
    private let recoveryMargin: Double

    /// Per provider: the percentages already fired and not yet recovered.
    private var firedBelow: [String: Set<Double>] = [:]

    public init(recoveryMargin: Double = 1.0) {
        self.recoveryMargin = recoveryMargin
    }

    /// Advances the crossing state for one provider refresh and returns the
    /// thresholds newly crossed by this update — empty on every other refresh.
    /// Returned most-severe-first (highest boundary first).
    public mutating func crossings(
        providerId: String,
        percentRemaining: Double,
        thresholds: [QuotaAlertThreshold]
    ) -> [QuotaAlertThreshold] {
        var fired = firedBelow[providerId] ?? []
        var crossed: [QuotaAlertThreshold] = []

        for threshold in thresholds {
            if percentRemaining < threshold.percent {
                if fired.insert(threshold.percent).inserted {
                    crossed.append(threshold)
                }
            } else if percentRemaining >= threshold.percent + recoveryMargin {
                // Recovered with margin: the threshold may fire on the next dip.
                fired.remove(threshold.percent)
            }
        }

        firedBelow[providerId] = fired
        return crossed.sorted(by: >)
    }
}
