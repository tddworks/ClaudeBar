import Foundation

/// *The week turned, and its recap hasn't gone out* — the one owner of the
/// recap's moment, beside `QuotaAlerts` and `StatusAlerts` in Alerting. It
/// follows the Monitor's refreshes (never a timer of its own), asks the pure
/// `RecapDue` whether a week's recap is due, reads the recap through
/// `WeeklyRecaps` — the card's own read, never a second one — marks the week
/// sent, and tells the recap destinations ([design](docs/features/alerting/recap-alerts/design.md)).
@MainActor
public final class RecapAlerts {
    private let destination: any RecapDestination
    private let recaps: WeeklyRecaps
    /// Each provider's name, by id, asked at the send — handed the words,
    /// never looking them up, as `StatusAlerts` is handed the login's name.
    private let names: @MainActor () -> [String: String]
    private let memory: any RecapSentRepository
    private let calendar: Calendar
    private let now: () -> Date
    /// One review at a time, as `WeeklyRecaps` reads one at a time: the read
    /// suspends, and refreshes keep arriving meanwhile.
    private var underWay = false

    /// - Parameters:
    ///   - destination: who hears the recap — the webhooks, today.
    ///   - recaps: the card's read of both weeks, shared with the All page.
    ///   - names: each provider's name by id, as the lineup says it.
    ///   - memory: when the last recap went out.
    ///   - calendar: the person's calendar (`DataSources.calendar()`), the
    ///     one the weeks are read in and written in.
    ///   - now: the clock.
    public init(destination: any RecapDestination,
                recaps: WeeklyRecaps,
                names: @escaping @MainActor () -> [String: String],
                memory: any RecapSentRepository,
                calendar: Calendar,
                now: @escaping () -> Date = Date.init) {
        self.destination = destination
        self.recaps = recaps
        self.names = names
        self.memory = memory
        self.calendar = calendar
        self.now = now
    }

    /// Follows every refresh of `monitor`, as `StatusAlerts` does. A paused
    /// login is never refreshed, so it never brings a moment; a week whose
    /// every refresh failed waits for one that lands.
    public func follow(_ monitor: QuotaMonitor) {
        monitor.onRefreshed { _ in await self.review() }
    }

    /// The once-per-week moment: the week turned, the closed week hasn't gone
    /// out, and it added up to something. The week is marked sent once its
    /// recap has been read — whether or not a webhook wanted it, and whether
    /// or not a POST arrives — so the next week is the next recap.
    public func review() async {
        guard !underWay else { return }
        underWay = true
        defer { underWay = false }

        let date = now()
        guard let due = RecapDue.week(containing: date, lastSentAt: memory.lastSent(), calendar: calendar) else { return }
        await recaps.readIfStale()
        // A read that didn't finish leaves the previous read standing — not
        // this week's. Wait for a refresh whose read completes.
        guard recaps.weekShown == DateRange.week(containing: date, calendar: calendar),
              let recap = recaps.recap(for: .lastWeek) else { return }
        memory.setLastSent(date)
        // A week that added up to nothing says nothing: silence, not zeros.
        guard !recap.isEmpty else { return }
        await destination.announce(RecapAlert(recap: recap, week: due.week, calendar: calendar, names: names()))
    }
}
