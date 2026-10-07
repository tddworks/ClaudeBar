package com.tddworks.claudebar.leaderboard

import com.tddworks.claudebar.storage.Revision
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlin.coroutines.cancellation.CancellationException

/**
 * This Mac's membership of the leaderboard — a name, a key in your pocket, and the providers you
 * agreed to share. It owns what may leave the Mac: only shared providers, and only providers
 * with token logs can be shared. It never holds a ranking; the server owns that. Commands that
 * fail throw [LeaderboardError] and leave the membership as it was. [revision] moves after
 * every change, for the UI (MODULAR_DESIGN §5).
 */
public class LeaderboardMembership internal constructor(
    private val api: LeaderboardAPI,
    private val keys: SigningKeyStore,
    private val settings: LeaderboardSettingsRepository,
    private val logs: TokenLogs,
    private val calendar: MemberCalendar,
    private val random: RandomBytes,
) {
    var username: Username? = null
        private set
    var sharing: Set<String> = emptySet()
        private set
    var isVisible = true
        private set
    var lastUploadSeconds: Double? = null
        private set

    /** Your country is on the globe: kept by the server from where your requests come from, never sent by this Mac. Off until you opt in. */
    var sharesCountry = false
        private set
    private var globeHintDismissed = false

    /** Where people on the board can find you, when you added it. Not verified. */
    var link: ProfileLink? = null
        private set

    /** Whether ClaudeBar takes part at all: the tab, and uploads. Off is a pause, kept on this Mac only: the membership stays as it was. */
    var isOn = true
        private set
    private var key: SigningKey? = null

    private val changes = Revision()
    val revision: StateFlow<Long> = changes.flow

    init {
        restore()
    }

    val isJoined: Boolean get() = credentials != null

    /** Providers that can be ticked: those with token logs on this Mac. */
    val shareableProviders: Set<String> get() = logs.providersWithLogs

    internal val credentials: MemberCredentials?
        get() {
            val username = username ?: return null
            val key = key ?: return null
            return MemberCredentials(username, key)
        }

    /** What an upload is signed with: nothing while not joined or turned off, so nothing leaves the Mac and `lastUpload` stays where it stopped. */
    internal val uploadCredentials: MemberCredentials? get() = if (isOn) credentials else null

    // — Joining and leaving —

    internal suspend fun join(username: Username, sharing: Set<String>, sharesCountry: Boolean = false, link: ProfileLink? = null) {
        if (sharing.isEmpty()) throw LeaderboardError.NothingShared
        requireShareable(sharing)
        val key = SigningKey.generate(random)
        api.join(username.value, key.publicKey)
        keys.save(key.rawRepresentation)
        this.key = key
        this.username = username
        this.sharing = sharing
        isVisible = true
        lastUploadSeconds = null
        this.sharesCountry = false
        globeHintDismissed = false
        this.link = null
        save()
        if (sharesCountry) attempt { setSharesCountry(true) }
        if (link != null) attempt { setLink(link) }
    }

    /**
     * Deletes the member and every row on the server first; the key is forgotten only once the
     * server confirmed, or the name would be lost with the data still there.
     */
    internal suspend fun leave() {
        val credentials = credentials ?: throw LeaderboardError.NotJoined
        api.leave(credentials)
        forget()
    }

    /**
     * The server no longer knows this member (swept a day after joining with nothing uploaded, or
     * removed): forget it here too, so the join form shows again instead of a key that will never
     * be accepted.
     */
    internal fun forgetUnknownMember() = forget()

    private fun forget() {
        keys.delete()
        key = null
        username = null
        sharing = emptySet()
        isVisible = true
        lastUploadSeconds = null
        sharesCountry = false
        globeHintDismissed = false
        link = null
        settings.saveLeaderboardRecord(null)
        changed()
    }

    // — On and off —

    /** Hides the Leaderboard and stops uploads. A member stays a member. */
    fun turnOff() {
        isOn = false
        settings.setLeaderboardOn(false)
        changed()
    }

    fun turnOn() {
        isOn = true
        settings.setLeaderboardOn(true)
        changed()
    }

    // — What is shared —

    internal fun share(provider: String) {
        requireShareable(setOf(provider))
        sharing = sharing + provider
        save()
    }

    fun stopSharing(provider: String) {
        sharing = sharing - provider
        save()
    }

    /** The days that may leave the Mac: shared providers only, each provider's logins added up per day, days without tokens left out. */
    internal fun dailyTokens(logins: List<LoginDays>): List<DailyTokens> =
        if (isJoined) DailyTokens.summed(logins, sharing, calendar) else emptyList()

    internal fun recordUpload(atSeconds: Double) {
        lastUploadSeconds = atSeconds
        save()
    }

    // — Name and visibility —

    internal suspend fun setVisible(visible: Boolean) {
        val credentials = credentials ?: throw LeaderboardError.NotJoined
        api.update(MemberChange(visible = visible), credentials)
        isVisible = visible
        save()
    }

    internal suspend fun rename(newName: Username) {
        val credentials = credentials ?: throw LeaderboardError.NotJoined
        api.update(MemberChange(username = newName.value), credentials)
        username = newName
        save()
    }

    // — Profile link —

    /** Adds, replaces or — with `null` — removes your profile link on the board. */
    internal suspend fun setLink(newLink: ProfileLink?) {
        val credentials = credentials ?: throw LeaderboardError.NotJoined
        val change = newLink?.let { MemberChange.LinkChange.Set(it) } ?: MemberChange.LinkChange.Remove
        api.update(MemberChange(link = change), credentials)
        link = newLink
        save()
    }

    // — The globe —

    /** Puts your country on the globe, or takes it off: the server forgets it at once when you turn this off. */
    internal suspend fun setSharesCountry(shares: Boolean) {
        val credentials = credentials ?: throw LeaderboardError.NotJoined
        api.update(MemberChange(sharesCountry = shares), credentials)
        sharesCountry = shares
        save()
    }

    /** The one-time *NEW* card that offers the globe, until you opt in or dismiss it. */
    val showsGlobeHint: Boolean get() = isJoined && !sharesCountry && !globeHintDismissed

    fun dismissGlobeHint() {
        globeHintDismissed = true
        save()
    }

    // — Reading the board —

    internal suspend fun myStanding(view: BoardView): MemberSummary {
        val credentials = credentials ?: throw LeaderboardError.NotJoined
        return api.me(view, credentials)
    }

    // — Private —

    private fun requireShareable(providers: Set<String>) {
        (providers - logs.providersWithLogs).sorted().firstOrNull()?.let { throw LeaderboardError.NotShareable(it) }
    }

    /** Like Swift's `try?`: a step after joining that may fail without undoing the join. */
    private suspend fun attempt(step: suspend () -> Unit) {
        try {
            step()
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
        }
    }

    private fun restore() {
        isOn = settings.isLeaderboardOn()
        val record = settings.leaderboardRecord() ?: return
        val name = Username.of(record.username) ?: return
        val key = keys.load()?.let(SigningKey::of) ?: return
        this.key = key
        username = name
        sharing = record.sharing.toSet()
        isVisible = record.visible
        lastUploadSeconds = record.lastUploadSeconds
        sharesCountry = record.sharesCountry
        globeHintDismissed = record.globeHintDismissed
        link = record.link
    }

    private fun save() {
        val username = username
        if (username != null) {
            settings.saveLeaderboardRecord(
                LeaderboardRecord(
                    username = username.value,
                    sharing = sharing,
                    visible = isVisible,
                    lastUploadSeconds = lastUploadSeconds,
                    sharesCountry = sharesCountry,
                    globeHintDismissed = globeHintDismissed,
                    link = link,
                ),
            )
        }
        changed()
    }

    private fun changed() {
        changes.bump()
    }
}
