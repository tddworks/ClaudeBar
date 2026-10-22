import Foundation

/// WILL IT LAST UNTIL IT RESETS — a read of the quota's `SpendRate` against
/// its `Window`, carried forward to zero.
///
/// `Pace` names how fast (*Running hot*); `Forecast` names the moment (it runs
/// out 34 minutes before it refills). Both read the one rate, so they never
/// disagree: `.runsOut` ⇔ `Pace` is *Running hot*.
public enum Forecast: Sendable, Equatable, Hashable {
    /// At this rate the quota is still there when the window refills, or
    /// within `SpendRate.margin` of it.
    case lastsUntilReset
    /// At this rate the quota reaches zero in `in`, `beforeReset` ahead of the
    /// window refilling.
    case runsOut(in: Duration, beforeReset: Duration)

    /// What the rate says about this window, or `nil` when there is nothing to
    /// carry forward: the quota is used up (it has already run out), or the
    /// window states no length or no reset.
    public init?(rate: SpendRate, window: Window, at now: Date) {
        let percentLeft = 100 - rate.percentUsed
        guard percentLeft > 0,
              let length = window.length, length > 0,
              let untilReset = window.untilReset(at: now)
        else { return nil }

        guard rate.runsOutBeforeReset else {
            self = .lastsUntilReset
            return
        }
        let runsOutIn = percentLeft * length / (100 * rate.value)
        self = .runsOut(in: .seconds(runsOutIn), beforeReset: .seconds(max(0, untilReset - runsOutIn)))
    }

    /// Whether the quota lasts until its window refills.
    public var outlastsReset: Bool {
        self == .lastsUntilReset
    }
}
