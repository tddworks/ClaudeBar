package com.tddworks.claudebar.alerting

import com.tddworks.claudebar.diagnostics.AppLog
import com.tddworks.claudebar.providers.Outcome
import com.tddworks.claudebar.providers.outcome
import com.tddworks.claudebar.quotas.StatusPolicy
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlin.coroutines.cancellation.CancellationException

/**
 * Keeps a linked Notify! device in sync with the quotas.
 *
 * Deliberately free of judgement: what to show and when to send it is [NotifyPayloadBuilder]'s
 * and [NotifyPublishGate]'s. This gathers state, asks those two, and performs the I/O the answer
 * implies — one publish at a time, since two overlapping writes to the same tile can land out of
 * order and leave an older reading standing on the Lock Screen.
 *
 * It offers the payload on every [changes] and once a [TICK_SECONDS]: a change the gate held back
 * must be offered again once the interval passed, and the tile must be re-sent before the
 * gateway's two-hour reaper ends it. Nothing changes on a clock by itself.
 */
public class NotifyPublisher internal constructor(
    private val settings: NotifySettingsRepository,
    private val publisher: NotifyPublishing,
    /** Every quota window the lineup reports, with the name each login goes by. */
    private val readings: () -> List<NotifyQuotaReading>,
    private val statusPolicy: () -> StatusPolicy,
    /** One value each time anything a payload is built from may have changed. */
    private val changes: Flow<Unit>,
    private val now: () -> Double,
    private val scope: CoroutineScope,
    private val builder: NotifyPayloadBuilder = NotifyPayloadBuilder(),
    private val gate: NotifyPublishGate = NotifyPublishGate(),
) {
    private val publishing = Mutex()
    private var running: Job? = null

    /** What the phone is believed to show, and when each surface was last written. */
    private var record: NotifyPublishRecord? = null

    /** While set, tile writes are skipped: the gateway is in push-to-start backoff, and every attempt inside it lengthens the wait. */
    private var tileSuppressedUntil: Double? = null

    /** While set, Home Screen tile writes are skipped: the gateway has that surface switched off server side. */
    private var screenTileSuppressedUntil: Double? = null

    /** Starts offering payloads; nothing is sent while publishing is switched off. */
    @OptIn(FlowPreview::class)
    public fun start() {
        if (running != null) return
        running = scope.launch {
            launch { changes.debounce(DEBOUNCE_MS).collect { offer() } }
            while (true) {
                delay((TICK_SECONDS * 1000).toLong())
                offer()
            }
        }
    }

    public fun stop() {
        running?.cancel()
        running = null
    }

    /**
     * Publishes the current payload whether the gate would allow it or not — the moment the person
     * saves new credentials or presses publish. The only forced path: two publishers writing the
     * same handles is how a phone ends up with two Live Activities.
     *
     * Null when everything the payload asked for was written, else a message for the person.
     */
    public suspend fun publishNow(): String? {
        if (!settings.isNotifyEnabled()) return "Publishing to Notify! is switched off."
        // Said before the payload is built: an empty payload can't tell "every surface off" from "no quota yet".
        if (!settings.isNotifyLiveActivityEnabled() && !settings.isNotifyWidgetEnabled() && !settings.isNotifyScreenWidgetEnabled()) {
            return "The Live Activity, the Lock Screen widget and the Home Screen widget are all switched off, so there is nothing to send."
        }
        // A publish already running finishes first: a cancelled start may already have made a tile whose id would be lost.
        return publishing.withLock {
            // Clearing the record is what forces the write; the gateway's own backoff is left in place.
            record = null
            settings.notifyDeviceLink()?.let { link ->
                if (!link.kind.supportsAnySurface) return@withLock link.kind.widgetUnsupportedReason ?: link.kind.liveActivityUnsupportedReason
            }
            val payload = currentPayload()
            if (payload.isEmpty) return@withLock "There is no quota to send yet. Give a provider time to report one."
            val at = now()
            val decision = withoutSuppressedSurfaces(gate.decide(payload, null, at), at)
            if (decision.publishesNothing) {
                return@withLock if (tileSuppressedUntil != null) {
                    "Notify! is still holding off Live Activity starts. ClaudeBar will retry on its own."
                } else {
                    "Notify! is not serving Home Screen widgets yet. ClaudeBar will try again later."
                }
            }
            publish(payload, decision, at)
        }
    }

    /** *Check device*: what the gateway knows the linked device as — "Apollo (iOS)" — or why it couldn't say. */
    public suspend fun deviceDescription(link: NotifyDeviceLink): Outcome<String> = outcome { publisher.deviceInfo(link).displayDescription }

    /** Offers the payload to the gate, unless publishing is off or a publish is already running. */
    internal suspend fun offer() {
        if (!settings.isNotifyEnabled()) return
        if (!publishing.tryLock()) return
        try {
            val payload = currentPayload()
            if (payload.isEmpty) return
            val at = now()
            val decision = withoutSuppressedSurfaces(gate.decide(payload, record, at), at)
            if (decision.publishesNothing) return
            publish(payload, decision, at)
        } finally {
            publishing.unlock()
        }
    }

    private fun currentPayload(): NotifyPayload = builder.payload(
        readings = readings(),
        nowSeconds = now(),
        gaugeSelection = NotifyGaugeSelection(settings.notifyGaugeProviderId(), settings.notifyGaugeQuotaKey()),
        includesTile = settings.isNotifyLiveActivityEnabled(),
        includesGauge = settings.isNotifyWidgetEnabled(),
        includesScreenTile = settings.isNotifyScreenWidgetEnabled(),
        statusPolicy = statusPolicy(),
    )

    /** Drops the surfaces inside a wait the gateway asked for, and forgets each wait once it passed. */
    private fun withoutSuppressedSurfaces(decision: NotifyPublishDecision, at: Double): NotifyPublishDecision {
        tileSuppressedUntil?.let { if (at >= it) tileSuppressedUntil = null }
        screenTileSuppressedUntil?.let { if (at >= it) screenTileSuppressedUntil = null }
        return NotifyPublishDecision(
            publishesTile = decision.publishesTile && tileSuppressedUntil == null,
            publishesGauge = decision.publishesGauge,
            publishesScreenTile = decision.publishesScreenTile && screenTileSuppressedUntil == null,
        )
    }

    private enum class Surface(val label: String) { TILE("tile"), GAUGE("widget"), SCREEN_TILE("Home Screen widget") }

    /** Null when every surface the decision named was written, else the first failure as a message. */
    private suspend fun publish(payload: NotifyPayload, decision: NotifyPublishDecision, at: Double): String? {
        val link = settings.notifyDeviceLink() ?: run {
            // No device linked is the state the feature ships in, not a failure.
            AppLog.notifications.debug("Notify! publish skipped: no device linked")
            return NotifyPublishError.NotLinked.message
        }
        // Only the link knows where the payload is going: drop what this device can never show.
        val supported = NotifyPublishDecision(
            publishesTile = decision.publishesTile && link.supportsLiveActivity,
            publishesGauge = decision.publishesGauge && link.supportsWidget,
            publishesScreenTile = decision.publishesScreenTile && link.supportsScreenWidget,
        )
        if (supported.publishesNothing) {
            AppLog.notifications.debug("Notify! publish skipped: the linked ${link.kind.displayName} shows none of these surfaces")
            return null
        }
        // Each surface is written on its own: a tile the device refuses must not cost the widget.
        val failures = mutableListOf<String>()
        var sentTile = false
        var sentGauge = false
        var sentScreenTile = false
        val tile = payload.tile
        if (supported.publishesTile && tile != null) sendTile(tile, link)?.let { failures += it } ?: run { sentTile = true }
        val gauge = payload.gauge
        if (supported.publishesGauge && gauge != null) {
            write(Surface.GAUGE, link, { publisher.publishGauge(gauge, link, settings.notifyWidgetId()) }) { settings.setNotifyWidgetId(it) }
                ?.let { failures += it } ?: run { sentGauge = true }
        }
        // Last, with the content the Live Activity just carried: the Home Screen route takes the tile body unchanged.
        val screenTile = payload.screenTile
        if (supported.publishesScreenTile && screenTile != null) {
            write(Surface.SCREEN_TILE, link, { publisher.publishScreenTile(screenTile, link, settings.notifyScreenWidgetId()) }) {
                settings.setNotifyScreenWidgetId(it)
            }?.let { failures += it } ?: run { sentScreenTile = true }
        }
        // What was actually sent, not what was decided: a failed surface keeps the content it really shows.
        if (sentTile || sentGauge || sentScreenTile) {
            record = (record ?: NotifyPublishRecord(NotifyPayload.empty))
                .updated(payload, NotifyPublishDecision(sentTile, sentGauge, sentScreenTile), at)
        }
        return failures.firstOrNull()
    }

    private suspend fun sendTile(tile: NotifyTile, link: NotifyDeviceLink): String? = try {
        store(publisher.publishTile(tile, link, settings.notifyActivityId()), link, Surface.TILE) { settings.setNotifyActivityId(it) }
        null
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (_: NotifyPublishError.TileGone) {
        // The tile was dismissed and can never be updated again: start one fresh, exactly once.
        AppLog.notifications.info("Notify! tile was dismissed on the device, starting a new one")
        settings.setNotifyActivityId(null)
        write(Surface.TILE, link, { publisher.publishTile(tile, link, null) }) { settings.setNotifyActivityId(it) }
    } catch (error: Exception) {
        report(error, Surface.TILE)
        message(error)
    }

    private suspend fun write(surface: Surface, link: NotifyDeviceLink, send: suspend () -> String, keep: (String) -> Unit): String? = try {
        store(send(), link, surface, keep)
        null
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (error: Exception) {
        report(error, surface)
        message(error)
    }

    /**
     * Keeps a handle only while it still belongs to the saved link: the person may replace the
     * link while a request is in flight, and the next link must not inherit a stranger's tile.
     */
    private fun store(handle: String, link: NotifyDeviceLink, surface: Surface, keep: (String) -> Unit) {
        if (settings.notifyDeviceLink() != link) {
            AppLog.notifications.info("Notify! link changed while publishing, discarding the ${surface.label} handle it returned")
            return
        }
        keep(handle)
    }

    /** Every [NotifyPublishError] carries a sentence written for a person. */
    private fun message(error: Exception): String = error.message ?: error.toString()

    /**
     * Turns a failed write into the state change it implies, and one log line — never a device id
     * or a token. Every reaction is scoped to the surface that failed: the gateway answers every
     * credential problem with one 403, and the likeliest cause is one tile the person deleted.
     */
    private fun report(error: Exception, surface: Surface) {
        if (error !is NotifyPublishError) {
            // Its text may quote a URL, and every URL here carries the device token: the type is enough.
            AppLog.notifications.error("Notify! ${surface.label} publish failed: ${error::class.simpleName}")
            return
        }
        when (error) {
            NotifyPublishError.RejectedCredentials -> {
                forget(surface)
                AppLog.notifications.error("Notify! refused the stored ${surface.label}, forgetting its handle so the next publish creates a new one")
            }
            is NotifyPublishError.Backoff -> {
                // Push-to-start backoff is a Live Activity rule; it never silences a widget.
                if (surface != Surface.TILE) {
                    AppLog.notifications.warning("Notify! ${surface.label} publish was rate limited, retrying on a later tick")
                    return
                }
                tileSuppressedUntil = now() + error.retryAfterSeconds
                val hint = if (error.openingTheAppMayHelp) ", opening the Notify! app on the device may clear it sooner" else ""
                AppLog.notifications.warning("Notify! is holding off Live Activity starts for ${kotlin.math.round(error.retryAfterSeconds).toLong()}s$hint")
            }
            is NotifyPublishError.SurfaceSwitchedOff -> {
                if (surface != Surface.SCREEN_TILE) {
                    AppLog.notifications.info("Notify! has the ${surface.label} switched off at the moment, retrying on a later tick")
                    return
                }
                // Nothing this app does moves that switch: ask again in hours, not every tick.
                screenTileSuppressedUntil = now() + SWITCHED_OFF_SUPPRESSION_SECONDS
                AppLog.notifications.info("Notify! is not serving Home Screen widgets yet, pausing that surface for six hours")
            }
            is NotifyPublishError.DeliveryUnconfirmed -> {
                // A tile may already exist: keep the id so the next update addresses it instead of starting a second.
                error.activityId?.takeIf { it.isNotEmpty() }?.let { settings.setNotifyActivityId(it) }
                AppLog.notifications.warning("Notify! could not confirm the tile started, updating it on the next tick")
            }
            // Its text quotes the transport's, which may hold the URL and so the token.
            is NotifyPublishError.TransportFailed -> AppLog.notifications.error("Notify! ${surface.label} publish could not reach the gateway")
            else -> AppLog.notifications.error("Notify! ${surface.label} publish failed: ${error.message}")
        }
    }

    private fun forget(surface: Surface) = when (surface) {
        Surface.TILE -> settings.setNotifyActivityId(null)
        Surface.GAUGE -> settings.setNotifyWidgetId(null)
        Surface.SCREEN_TILE -> settings.setNotifyScreenWidgetId(null)
    }

    internal companion object {
        /** The tile's own minimum interval: the finest cadence that can change an answer. */
        const val TICK_SECONDS = 60.0
        const val DEBOUNCE_MS = 500L
        const val SWITCHED_OFF_SUPPRESSION_SECONDS = 6 * 60 * 60.0
    }
}
