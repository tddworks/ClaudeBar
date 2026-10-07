package com.tddworks.claudebar.alerting

import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/** *Quota alerts* as a notification: the login, the person's percentage, and what is left. */
class QuotaAlertNotificationsTest {
    private class Sent : AlertSender {
        var title = ""
        var body = ""
        var category = ""

        override suspend fun requestPermission() = true
        override suspend fun send(title: String, body: String, categoryIdentifier: String) {
            this.title = title
            this.body = body
            this.category = categoryIdentifier
        }
        override suspend fun send(title: String, body: String, categoryIdentifier: String, button: String, link: String) = Unit
    }

    @Test
    fun `should name the login, the percentage it fell below and what is left`() = runBlocking {
        val sent = Sent()

        QuotaAlertNotifications(sent).announce(QuotaAlert(login = "Claude · work", below = 35, left = 34))

        assertEquals("Claude · work is below 35%", sent.title)
        assertEquals("34% left.", sent.body)
        assertEquals(QuotaAlertNotifications.CATEGORY, sent.category)
    }
}
