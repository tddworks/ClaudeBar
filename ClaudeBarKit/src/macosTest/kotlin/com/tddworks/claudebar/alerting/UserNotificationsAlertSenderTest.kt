package com.tddworks.claudebar.alerting

import kotlinx.coroutines.runBlocking
import platform.Foundation.NSBundle
import kotlin.test.Test
import kotlin.test.assertFalse

/**
 * The test binary has no bundle identifier, which is when UserNotifications is unavailable:
 * the sender must say no and stay quiet rather than crash. (With one, it would ask the person.)
 */
class UserNotificationsAlertSenderTest {
    private val sender = UserNotificationsAlertSender()
    private val bundled = NSBundle.mainBundle.bundleIdentifier != null

    @Test
    fun `should give no permission when the app has no bundle to send alerts from`() = runBlocking {
        if (bundled) return@runBlocking
        assertFalse(sender.requestPermission())
    }

    @Test
    fun `should send nothing and not fail when the app has no bundle to send alerts from`() = runBlocking {
        if (bundled) return@runBlocking
        sender.send("ClaudeBar Quota Alert", "Your quota is running low.", "QUOTA_ALERT")
        sender.send("Claude: personal is at 8%", "work has 81% left.", "IN_USE", "Undo", "claudebar://use")
    }
}
