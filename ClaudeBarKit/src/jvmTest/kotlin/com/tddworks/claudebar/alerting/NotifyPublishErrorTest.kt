package com.tddworks.claudebar.alerting

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.Arguments
import org.junit.jupiter.params.provider.CsvSource
import org.junit.jupiter.params.provider.MethodSource

/** What the Notify! pane says when a Live Activity can't be published, and whether waiting will help. */
internal class NotifyPublishErrorTest {
    companion object {
        @JvmStatic
        fun messages() = listOf(
            Arguments.of(NotifyPublishError.NotLinked, "Add your Notify! device ID and token before publishing."),
            Arguments.of(NotifyPublishError.RejectedCredentials, "Notify! rejected these credentials. Copy the device ID and token again from the Notify! app."),
            Arguments.of(NotifyPublishError.LiveActivityUnavailable(""), "This device cannot show a Live Activity yet. Open the Notify! app once on the device."),
            Arguments.of(NotifyPublishError.LiveActivityUnavailable("Live Activities are off"), "Live Activities are off"),
            Arguments.of(NotifyPublishError.TileGone, "The Live Activity was dismissed on the device. ClaudeBar will start a new one."),
            Arguments.of(NotifyPublishError.InvalidPayload(""), "Notify! rejected the content of this update."),
            Arguments.of(NotifyPublishError.InvalidPayload("title too long"), "title too long"),
            Arguments.of(NotifyPublishError.DeliveryUnconfirmed(null), "Notify! could not confirm the Live Activity started. ClaudeBar will check again on the next update."),
            Arguments.of(NotifyPublishError.TransportFailed("offline"), "Could not reach Notify!: offline"),
            Arguments.of(NotifyPublishError.SurfaceSwitchedOff(""), "Notify! has this widget switched off at the moment. ClaudeBar will try again later."),
            Arguments.of(NotifyPublishError.SurfaceSwitchedOff("Paused by you"), "Paused by you"),
            Arguments.of(NotifyPublishError.UnexpectedStatus(503), "Notify! answered with HTTP 503."),
            Arguments.of(NotifyPublishError.MalformedResponse, "Notify! sent a response ClaudeBar could not read."),
        )
    }

    @ParameterizedTest
    @MethodSource("messages")
    fun `should tell the person what went wrong in words they can act on`(error: NotifyPublishError, message: String) {
        assertEquals(message, error.message)
    }

    @ParameterizedTest
    @CsvSource(
        "30.0, a minute",
        "60.0, a minute",
        "300.0, 5 minutes",
        "3540.0, 59 minutes",
        "3599.0, an hour",
        "3600.0, an hour",
        "7200.0, 2 hours",
    )
    fun `should say how long Notify! is waiting in minutes or hours`(seconds: Double, wait: String) {
        val error = NotifyPublishError.Backoff(seconds, openingTheAppMayHelp = false)
        assertEquals("Notify! is waiting $wait before another Live Activity.", error.message)
    }

    @Test
    fun `should suggest opening the Notify! app when that may end the wait sooner`() {
        val error = NotifyPublishError.Backoff(600.0, openingTheAppMayHelp = true)
        assertEquals(
            "Notify! is waiting 10 minutes before another Live Activity. Opening the Notify! app on the device may clear it sooner.",
            error.message,
        )
    }

    @Test
    fun `should know how long to wait only when Notify! asked to wait`() {
        assertEquals(90.0, NotifyPublishError.Backoff(90.0, openingTheAppMayHelp = false).retryAfter)
        assertNull(NotifyPublishError.TransportFailed("offline").retryAfter)
        assertNull(NotifyPublishError.NotLinked.retryAfter)
    }
}
