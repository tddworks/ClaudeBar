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

    /// How many points the share used may sit either side of the share of the
    /// window gone and still read as on the line: the margin Pace has always
    /// had, so a point or two of drift is *On track*, not an alarm.
    public static let margin: Double = 5

    /// Whether, at this rate, the quota runs out before the window refills:
    /// used more than `margin` points ahead of the share of the window gone.
    /// Within the margin it reads as lasting until the reset. `Pace` (*Running
    /// hot*) and `Forecast` (*Runs out…*) both read this, so they never disagree.
    public var runsOutBeforeReset: Bool {
        percentUsed - percentTimeElapsed > Self.margin
    }

    /// Whether it is spent more than `margin` points behind the share of the
    /// window gone: *Room to spare*.
    public var hasRoomToSpare: Bool {
        percentTimeElapsed - percentUsed > Self.margin
    }
}
