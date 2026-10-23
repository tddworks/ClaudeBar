import Foundation
import Quotas

/// *Is this week's recap due?* — the once-a-calendar-week answer, pure: the
/// calendar's week holding `now`, against the week the last send was for, and
/// nothing else. Due from the week's first moment (the calendar's own first
/// weekday, never a fixed Monday); the recap it names is of the week that
/// closed. No timer runs and none is tested — the decider asks at every
/// refresh, so a week that closed while the Mac slept is asked about at the
/// first refresh after ([design](docs/features/alerting/recap-alerts/design.md)).
public struct RecapDue: Sendable, Equatable {
    /// The week whose recap is due: the calendar's week before the one
    /// holding `now` — the week that closed. After an absence this is the
    /// week that closed last: one recap, never the weeks missed.
    public let week: DateRange

    /// The recap due at `now`, or nil while the week of the last send is
    /// still the week holding `now`. Never sent is due at once, so the first
    /// refresh after a recap webhook is added hears the week that closed.
    public static func week(containing now: Date, lastSentAt: Date?, calendar: Calendar) -> RecapDue? {
        let current = DateRange.week(containing: now, calendar: calendar)
        guard let sent = lastSentAt, current.contains(sent, calendar: calendar) else {
            return RecapDue(week: current.before(calendar: calendar))
        }
        return nil
    }

    private init(week: DateRange) {
        self.week = week
    }
}
