package com.tddworks.claudebar.alerting

import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/** *In use* news as a notification: what it says, and the one button that acts on it through `claudebar://use`. */
class InUseNotificationsTest {
    private class Sent : AlertSender {
        var title = ""
        var body = ""
        var category = ""
        var button = ""
        var link: String? = null

        override suspend fun requestPermission() = true
        override suspend fun send(title: String, body: String, categoryIdentifier: String) = Unit
        override suspend fun send(title: String, body: String, categoryIdentifier: String, button: String, link: String) {
            this.title = title
            this.body = body
            this.category = categoryIdentifier
            this.button = button
            this.link = link
        }
    }

    private fun send(kind: InUseNotifications.Kind, link: String): Sent = runBlocking {
        val sent = Sent()
        InUseNotifications(sent).announce(
            InUseNotifications.News(kind, providerName = "Claude", from = "personal", to = "work", fromLeft = 8, toLeft = 81, link = link),
        )
        sent
    }

    @Test
    fun `should name the login worth moving to, what each has left, and offer one button to move`() {
        val sent = send(InUseNotifications.Kind.WORTH_SWITCHING, "claudebar://use?provider=claude&account=work")

        assertEquals("Claude: personal is at 8%", sent.title)
        assertEquals("work has 81% left. Start new terminal sessions on work?", sent.body)
        assertEquals("Use for New Sessions", sent.button)
        assertEquals("claudebar://use?provider=claude&account=work", sent.link)
        assertEquals(InUseNotifications.CATEGORY, sent.category)
    }

    @Test
    fun `should say where new sessions go after a switch, with a button to undo it`() {
        val sent = send(InUseNotifications.Kind.SWITCHED, "claudebar://use?provider=claude&account=default")

        assertEquals("New Claude sessions now use work", sent.title)
        assertEquals("personal is at 8%. Sessions already running keep their login.", sent.body)
        assertEquals("Undo", sent.button)
        assertEquals("claudebar://use?provider=claude&account=default", sent.link)
    }
}
