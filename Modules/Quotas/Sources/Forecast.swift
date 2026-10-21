import Foundation

/// WHEN THIS WINDOW RUNS OUT — the projection `Pace` deliberately does not make.
///
/// `Pace` compares what is used against how much of the window has elapsed — a
/// judgement, inside the window, with no unit (*On track · Running hot · Room
/// to spare*). `Forecast` projects what is used forward to zero — a duration,
/// about the future: at the average pace this window has been spent, when does
/// it reach zero, and does that beat the reset. They answer different
/// questions, so they are different values, and one never stands in for the
/// other.
///
/// - Note: Interim — today's shape, moved unchanged into the kernel.
///   Final version (docs/architecture/CANONICAL_MODEL.md §1, §4, §5) —
///   `Forecast`, a DERIVED read on `Quota` (`quota.forecast`), `nil` without a
///   window and for a balance with no ceiling.
public struct Forecast: Sendable, Equatable, Hashable {
    /// When the quota reaches zero at the window's average pace.
    ///
    /// When `outlastsReset` it never reaches zero inside this window, so the
    /// value is the time until the reset — the horizon the run-out is pushed
    /// past — and the words never print a run-out.
    public let runsOutIn: Duration

    /// How long before the reset the run-out is; `nil` when the quota outlasts
    /// its reset.
    public let beforeReset: Duration?

    /// Whether the quota lasts past its reset, so it never runs out first.
    public let outlastsReset: Bool

    /// The observed span below which a rate is noise, not a forecast. A window
    /// a minute in has no honest run-out to name (CANONICAL §5).
    public static let minimumElapsed: TimeInterval = 60

    /// The words a surface prints when there is nothing to forecast.
    public static let noForecast = "No forecast yet"

    /// The qualifier every forecast carries: it is the window's average, not a
    /// promise about the next burst (CANONICAL §5).
    public static let paceQualifier = "at this pace"

    public init(runsOutIn: Duration, beforeReset: Duration?, outlastsReset: Bool) {
        self.runsOutIn = runsOutIn
        self.beforeReset = beforeReset
        self.outlastsReset = outlastsReset
    }

    /// The answer the facts give together: at the average rate this window has
    /// been spent (`usedPercent` over `elapsed` seconds), the time to zero is
    /// `leftPercent × elapsed ÷ usedPercent`.
    ///
    /// `nil` while the rate is still noise — less than `minimumElapsed`
    /// observed, or nothing used at all to divide by. A window spent at nothing
    /// never runs out and reads *Lasts until it resets*.
    public static func of(
        leftPercent: Double,
        usedPercent: Double,
        elapsed: TimeInterval,
        untilReset: TimeInterval
    ) -> Forecast? {
        guard elapsed >= minimumElapsed else { return nil }

        guard usedPercent > 0 else {
            return Forecast(runsOutIn: .seconds(untilReset), beforeReset: nil, outlastsReset: true)
        }

        // An over-quota card (`leftPercent` negative) has already run out: the
        // time to zero is nothing, never a negative lead over the reset.
        let runsOutIn = max(0, leftPercent * elapsed / usedPercent)
        guard runsOutIn < untilReset else {
            return Forecast(runsOutIn: .seconds(runsOutIn), beforeReset: nil, outlastsReset: true)
        }
        return Forecast(
            runsOutIn: .seconds(runsOutIn),
            beforeReset: .seconds(untilReset - runsOutIn),
            outlastsReset: false
        )
    }

    /// The sentence a card prints under *Resets in…*: *Runs out in 38m — 34m
    /// before it resets*, or *Lasts until it resets*.
    public var summary: String {
        guard !outlastsReset, let beforeReset else { return "Lasts until it resets" }
        return "Runs out in \(Self.durationText(runsOutIn)) — \(Self.durationText(beforeReset)) before it resets"
    }

    /// A compact duration the way the screen prints it: *38m*, *3h*, *1h 12m*,
    /// *2d 5h*. Under a minute stays in seconds.
    public static func durationText(_ duration: Duration) -> String {
        let total = max(0, Int(duration.components.seconds))
        if total < 60 { return "\(total)s" }

        let minutes = total / 60
        if minutes < 60 { return "\(minutes)m" }

        let hours = minutes / 60
        if hours < 24 {
            let remainder = minutes % 60
            return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
        }

        let days = hours / 24
        let remainder = hours % 24
        return remainder == 0 ? "\(days)d" : "\(days)d \(remainder)h"
    }
}