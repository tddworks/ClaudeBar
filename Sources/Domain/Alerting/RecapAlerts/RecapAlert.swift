import Foundation
import Quotas

/// The week that closed, added up — what a recap destination is told: the
/// `Recap` the card reads, the week it sums, in the calendar the week was
/// read in, and the providers named as the lineup names them. It is not an
/// `Alert`: an alert names a login and its provider, and the recap names the
/// week across every provider ([design](docs/features/alerting/recap-alerts/design.md)).
public struct RecapAlert: Sendable, Equatable {
    /// The week's read, in the one unit every provider offers.
    public let recap: Recap
    /// The week the recap sums — the one that closed. The recap's own range.
    public var week: DateRange { recap.range }
    /// The calendar the week was read in, holding the week's boundaries —
    /// where it starts and where it ends. What is written of the week (a
    /// biggest day, a week's run) is Gregorian in this calendar's zone, never
    /// a zone guess.
    public let calendar: Calendar
    /// Each provider's name, by id, as the lineup says it; a provider no
    /// longer kept is read as its id.
    public let names: [String: String]

    public init(recap: Recap, calendar: Calendar, names: [String: String]) {
        self.recap = recap
        self.calendar = calendar
        self.names = names
    }

    /// A part's name: the lineup's for a provider kept, its id otherwise.
    public func name(of part: Recap.Part) -> String {
        names[part.provider] ?? part.provider
    }
}
