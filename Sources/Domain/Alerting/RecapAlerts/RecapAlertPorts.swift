import Foundation
import Mockable

/// Who hears the week's recap: today the person's webhooks. The Mac's own
/// Monday notification is the idea the recap's design deferred — a second
/// conformer when it comes, and this port never moves.
@Mockable
public protocol RecapDestination: Sendable {
    func announce(_ recap: RecapAlert) async
}

/// When the last recap went out — the once-per-calendar-week memory, kept in
/// `settings.json` so a relaunch inside the week sends again never. The week
/// it falls in is `RecapDue`'s reading of it, never kept.
@Mockable
public protocol RecapSentRepository: Sendable {
    func lastSent() -> Date?
    func setLastSent(_ date: Date)
}
