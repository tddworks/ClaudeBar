package com.tddworks.claudebar.alerting

import kotlin.math.ceil
import kotlin.math.floor

/**
 * Why a publish to Notify! did not land, in words the Notify! pane prints ([message]). Its own
 * type rather than a `UsageError`: it is the opposite direction of travel, and half of these
 * name something only the person can do on their phone. The gateway answers a missing, wrong,
 * unknown or somebody else's credential with one identical 403, so [RejectedCredentials]
 * covers all four.
 */
internal sealed class NotifyPublishError : Exception() {
    /** No device id and token saved yet. */
    data object NotLinked : NotifyPublishError()

    /** The gateway refused the credentials, or the device is not ours. */
    data object RejectedCredentials : NotifyPublishError()

    /** The device cannot show a Live Activity yet; [reason] is the gateway's own explanation. */
    data class LiveActivityUnavailable(val reason: String) : NotifyPublishError()

    /** Dismissed or ended, so never updatable again: the caller forgets the handle and starts fresh. */
    data object TileGone : NotifyPublishError()

    /** Push-to-start backoff (30 min after 2, 3 h after 4, 6 h after 6); resets when a tile appears. */
    data class Backoff(val retryAfterSeconds: Double, val openingTheAppMayHelp: Boolean) : NotifyPublishError()

    /** A field the gateway would not accept, or a per-device ceiling (5 live tiles, 10 widgets). */
    data class InvalidPayload(val reason: String) : NotifyPublishError()

    /** Apple never answered a start: a tile may exist, so the handle is kept and polled, not restarted. */
    data class DeliveryUnconfirmed(val activityId: String?) : NotifyPublishError()

    /** The request never completed. */
    data class TransportFailed(val reason: String) : NotifyPublishError()

    /**
     * The gateway has this surface switched off (the Home Screen widget's kill switch). Reads
     * and deletes stay open; the remedy is to wait, not to change anything.
     */
    data class SurfaceSwitchedOff(val reason: String) : NotifyPublishError()

    data class UnexpectedStatus(val status: Int) : NotifyPublishError()

    data object MalformedResponse : NotifyPublishError()

    override val message: String
        get() = when (this) {
            NotLinked -> "Add your Notify! device ID and token before publishing."
            RejectedCredentials ->
                "Notify! rejected these credentials. Copy the device ID and token again from the Notify! app."
            is LiveActivityUnavailable -> reason.ifEmpty {
                "This device cannot show a Live Activity yet. Open the Notify! app once on the device."
            }
            TileGone -> "The Live Activity was dismissed on the device. ClaudeBar will start a new one."
            is Backoff -> if (openingTheAppMayHelp) {
                "Notify! is waiting ${minutes(retryAfterSeconds)} before another Live Activity. Opening the Notify! app on the device may clear it sooner."
            } else {
                "Notify! is waiting ${minutes(retryAfterSeconds)} before another Live Activity."
            }
            is InvalidPayload -> reason.ifEmpty { "Notify! rejected the content of this update." }
            is DeliveryUnconfirmed ->
                "Notify! could not confirm the Live Activity started. ClaudeBar will check again on the next update."
            is TransportFailed -> "Could not reach Notify!: $reason"
            is SurfaceSwitchedOff -> reason.ifEmpty {
                "Notify! has this widget switched off at the moment. ClaudeBar will try again later."
            }
            is UnexpectedStatus -> "Notify! answered with HTTP $status."
            MalformedResponse -> "Notify! sent a response ClaudeBar could not read."
        }

    /** How long to wait before trying again, when waiting is the remedy. */
    val retryAfter: Double? get() = (this as? Backoff)?.retryAfterSeconds

    /** Whether the same request unchanged could ever succeed: back off, or give up until something changes. */
    val isRetryable: Boolean
        get() = when (this) {
            is TransportFailed, is Backoff, is DeliveryUnconfirmed, is UnexpectedStatus, is SurfaceSwitchedOff -> true
            NotLinked, RejectedCredentials, is LiveActivityUnavailable, TileGone, is InvalidPayload, MalformedResponse -> false
        }

    private companion object {
        fun minutes(seconds: Double): String {
            val minutes = ceil(seconds / 60).toInt()
            if (minutes <= 1) return "a minute"
            if (minutes < 60) return "$minutes minutes"
            val hours = floor(minutes / 60.0 + 0.5).toInt()
            return if (hours == 1) "an hour" else "$hours hours"
        }
    }
}
