import Foundation

/// HOW FAST A QUOTA IS SPENT AGAINST ITS WINDOW — the share used over the
/// share of the window gone. At 1 it reaches zero exactly as the window
/// refills; above 1 it runs out first.
///
/// The one rate every reading of speed reads (CANONICAL_MODEL §5): `Pace`
/// (*On track · Running hot · Room to spare*), the pace tick's `PaceLevel`, the
/// pace-aware status and the `Forecast`. One used share and one noise floor,
/// so a card never says *On track* beside *Runs out before it resets*.
public struct SpendRate: Sendable, Equatable, Hashable {
    /// The share of the quota used (0-100, more when over quota).
    public let percentUsed: Double

    /// The share of the window gone (`noiseFloor`..<100).
    public let percentTimeElapsed: Double

    /// Below this share of the window gone, a rate is noise, not a pace:
    /// nine minutes of a 5-hour window, five hours of a week.
    public static let noiseFloor: Double = 3

    /// `nil` before `noiseFloor` percent of the window has gone, or once the
    /// window is over.
    public init?(percentUsed: Double, percentTimeElapsed: Double) {
        guard percentTimeElapsed >= Self.noiseFloor, percentTimeElapsed < 100 else { return nil }
        self.percentUsed = percentUsed
        self.percentTimeElapsed = percentTimeElapsed
    }

    /// Used ÷ gone: 0.5 is half as fast as the window passes, 2 twice as fast.
    public var value: Double {
        max(0, percentUsed) / percentTimeElapsed
    }

    /// Whether, at this rate, the quota is still there when the window refills.
    public var outlastsWindow: Bool {
        value <= 1
    }
}
