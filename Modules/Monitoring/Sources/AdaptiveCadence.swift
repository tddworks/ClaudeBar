import Foundation

/// *Refresh faster while a quota moves* (#642): the background wait, read
/// from the change since the previous background tick. A quota that rose by
/// a point halves the next wait, down to `QuotaMonitor.minimumInterval`; a
/// tick where nothing rose doubles it, back up to the chosen interval.
///
/// The change since the last tick, not the forecast: a 5-hour window quiet
/// for four hours paces as comfortable while its last twenty minutes burn
/// fast, which is when the person wants the number fresh. Provider floors
/// and the battery stretch still apply on top, in `QuotaMonitor`.
public struct AdaptiveCadence: Sendable {
    /// One quota as a tick saw it.
    public struct Reading: Sendable, Equatable {
        public let percentUsed: Double
        public let resetsAt: Date?

        public init(percentUsed: Double, resetsAt: Date?) {
            self.percentUsed = percentUsed
            self.resetsAt = resetsAt
        }
    }

    /// The rise, in points used, that counts as movement.
    public static let threshold: Double = 1

    /// How far a reset time may drift and still be the same window. A reset
    /// read as "in 3h 20m" lands a little differently every probe; a new
    /// window moves it by the window's length, hours.
    static let windowDrift: TimeInterval = 15 * 60

    /// The chosen interval: the wait never grows past it.
    public let ceiling: Duration
    private var wait: Duration
    private var last: [String: Reading]?

    public init(ceiling: Duration) {
        self.ceiling = ceiling
        self.wait = ceiling
    }

    /// The wait after a tick that read `readings`, keyed by login and quota.
    /// The first tick has nothing to compare, so it waits the chosen interval.
    public mutating func next(after readings: [String: Reading]) -> Duration {
        defer { last = readings }
        guard let last else { return wait }
        wait = Self.moved(from: last, to: readings)
            ? max(wait / 2, QuotaMonitor.minimumInterval)
            : min(wait * 2, ceiling)
        return wait
    }

    /// Whether any quota seen both times rose by `threshold` within one window.
    /// A quota that appears, falls or starts a new window is not movement.
    static func moved(from before: [String: Reading], to after: [String: Reading]) -> Bool {
        after.contains { key, now in
            guard let then = before[key], sameWindow(then.resetsAt, now.resetsAt) else { return false }
            return now.percentUsed - then.percentUsed >= threshold
        }
    }

    private static func sameWindow(_ a: Date?, _ b: Date?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (a?, b?): abs(a.timeIntervalSince(b)) <= windowDrift
        default: false
        }
    }
}
