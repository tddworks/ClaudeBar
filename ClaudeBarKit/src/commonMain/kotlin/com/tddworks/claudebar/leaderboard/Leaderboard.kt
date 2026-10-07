package com.tddworks.claudebar.leaderboard

import com.tddworks.claudebar.providers.Outcome
import com.tddworks.claudebar.providers.outcome
import com.tddworks.claudebar.providers.prettyJson
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch

/**
 * The leaderboard as the app runs it: the [membership], the [uploader], the schedule that keeps
 * the server current, and every command a page gives — answered with an [Outcome], never a
 * thrown error (MODULAR_DESIGN §5).
 */
public class Leaderboard internal constructor(
    public val membership: LeaderboardMembership,
    public val uploader: LeaderboardUploader,
    private val api: LeaderboardAPI,
    private val logs: TokenLogs,
    private val calendar: MemberCalendar,
    /** One value each time the Mac wakes. */
    private val wakes: Flow<Unit>,
    private val now: () -> Double,
    private val scope: CoroutineScope,
) {
    private var schedule: Job? = null

    /**
     * Uploads once soon after launch, then asks every five minutes and on wake; the uploader
     * decides whether the hour has passed. A timer's clock stops while the Mac sleeps, so it
     * can't keep the hour itself.
     */
    public fun start() {
        schedule?.cancel()
        schedule = scope.launch {
            launch { wakes.collect { uploader.uploadDue() } }
            delay(FIRST_UPLOAD_DELAY_MS)
            while (true) {
                uploader.uploadDue()
                delay(CHECK_INTERVAL_MS)
            }
        }
    }

    public fun stop() {
        schedule?.cancel()
        schedule = null
    }

    /** Joins, then sends the last thirty days in the background so the first rank shows without waiting an hour. */
    public suspend fun join(username: Username, sharing: Set<String>, sharesCountry: Boolean, link: ProfileLink?): Outcome<Unit> =
        outcome { membership.join(username, sharing, sharesCountry, link) }.also {
            if (it is Outcome.Done) scope.launch { uploader.uploadNow() }
        }

    /** Uploads now, whatever tab is open. Nothing happens when not joined. */
    public suspend fun refresh() {
        uploader.uploadNow()
    }

    /** Today's days for [providers], exactly as an upload would send them — for the join form's preview. */
    public suspend fun preview(providers: Set<String>): List<DailyTokens> =
        DailyTokens.summed(logs.days(DayRange.last(1, now(), calendar)), providers, calendar)

    /** Hides the tab and stops uploads; a member stays a member. */
    public fun turnOff() {
        membership.turnOff()
    }

    /** Brings the tab back and catches up at once on the days missed. */
    public fun turnOn() {
        membership.turnOn()
        scope.launch { uploader.uploadNow() }
    }

    public fun share(provider: String): Outcome<Unit> = outcome { membership.share(provider) }

    public suspend fun leave(): Outcome<Unit> = outcome { membership.leave() }

    public suspend fun rename(newName: Username): Outcome<Unit> = outcome { membership.rename(newName) }

    public suspend fun setVisible(visible: Boolean): Outcome<Unit> = outcome { membership.setVisible(visible) }

    public suspend fun setLink(link: ProfileLink?): Outcome<Unit> = outcome { membership.setLink(link) }

    public suspend fun setSharesCountry(shares: Boolean): Outcome<Unit> = outcome { membership.setSharesCountry(shares) }

    public suspend fun myStanding(view: BoardView): Outcome<MemberSummary> = outcome { membership.myStanding(view) }

    /** *Export my data*: everything the server holds about you over thirty days, as a JSON file's text. */
    public suspend fun exportMyData(): Outcome<String> = outcome {
        prettyJson(LeaderboardWire.encode(membership.myStanding(BoardView(BoardPeriod.THIRTY_DAYS))), "")
    }

    public suspend fun board(view: BoardView): Outcome<List<Standing>> = outcome { api.board(view) }

    public suspend fun globe(): Outcome<GlobeSummary> = outcome { api.globe(BoardView(BoardPeriod.THIRTY_DAYS)) }

    internal companion object {
        const val FIRST_UPLOAD_DELAY_MS = 30_000L
        const val CHECK_INTERVAL_MS = 5 * 60_000L
    }
}
