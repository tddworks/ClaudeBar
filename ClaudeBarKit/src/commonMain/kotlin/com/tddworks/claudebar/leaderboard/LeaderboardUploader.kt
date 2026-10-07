package com.tddworks.claudebar.leaderboard

import com.tddworks.claudebar.storage.Revision
import com.tddworks.claudebar.diagnostics.AppLog
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlin.coroutines.cancellation.CancellationException

/**
 * Sends the shared days to the server. The first upload sends the last thirty days; each later
 * one resumes from the day of the last good upload, so a missed hour or a Mac asleep for days
 * heals itself. Re-sending a day replaces it on the server, never adds.
 */
public class LeaderboardUploader internal constructor(
    private val membership: LeaderboardMembership,
    private val logs: TokenLogs,
    private val api: LeaderboardAPI,
    private val calendar: MemberCalendar,
    private val now: () -> Double,
) {
    /** Why the last upload failed, until one succeeds. */
    internal var lastError: LeaderboardError? = null
        private set

    /** Why the last upload failed, in the person's words, until one succeeds. */
    val lastFailure: String? get() = lastError?.message
    var isUploading = false
        private set

    private val changes = Revision()
    val revision: StateFlow<Long> = changes.flow

    /**
     * Uploads when an hour has passed since the last good upload, by the wall clock: callers may
     * ask as often as they like, and a Mac that slept through the hour uploads on the first ask
     * after it wakes.
     */
    suspend fun uploadDue() {
        val lastUpload = membership.lastUploadSeconds
        if (lastUpload != null && now() - lastUpload < INTERVAL_SECONDS) return
        uploadNow()
    }

    /** Uploads at once, hour or not: an upload the person asked for. */
    suspend fun uploadNow() {
        val credentials = membership.uploadCredentials ?: return
        if (isUploading) return
        isUploading = true
        changes.bump()
        try {
            val now = now()
            val tokens = membership.dailyTokens(logs.days(range(now)))
            try {
                if (tokens.isNotEmpty()) api.upload(tokens, credentials)
                membership.recordUpload(now)
                lastError = null
            } catch (e: CancellationException) {
                throw e
            } catch (_: LeaderboardError.Unauthorized) {
                membership.forgetUnknownMember()
                lastError = null
                AppLog.network.info("Leaderboard no longer knows this member; forgot the membership here")
            } catch (e: Exception) {
                val error = e as? LeaderboardError ?: LeaderboardError.Unreachable
                lastError = error
                AppLog.network.info("Leaderboard upload failed: ${error.message}")
            }
        } finally {
            isUploading = false
            changes.bump()
        }
    }

    private fun range(now: Double): DayRange {
        val window = DayRange.last(WINDOW_DAYS, now, calendar)
        val lastUpload = membership.lastUploadSeconds
        if (lastUpload == null || lastUpload <= window.firstSeconds) return window
        return DayRange.of(lastUpload, now, calendar)
    }

    companion object {
        const val WINDOW_DAYS = 30
        const val INTERVAL_SECONDS = 60.0 * 60
    }
}
