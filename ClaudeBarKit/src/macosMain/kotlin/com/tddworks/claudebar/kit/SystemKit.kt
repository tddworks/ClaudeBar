package com.tddworks.claudebar.kit

import com.tddworks.claudebar.activity.FileHookSettings
import com.tddworks.claudebar.activity.HookHttpServer
import com.tddworks.claudebar.activity.HookInstaller
import com.tddworks.claudebar.activity.PortDiscovery
import com.tddworks.claudebar.activity.SessionAnnouncer
import com.tddworks.claudebar.activity.SessionMonitor
import com.tddworks.claudebar.activity.SessionTracking
import com.tddworks.claudebar.activity.SystemProcessLiveness
import com.tddworks.claudebar.alerting.UserNotificationsAlertSender
import com.tddworks.claudebar.storage.SettingsFile
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import platform.Foundation.NSDate
import platform.Foundation.NSHomeDirectory
import platform.Foundation.timeIntervalSince1970

/** The kit on this Mac: its real files, servers and notifications. */
public fun ClaudeBarCore.Companion.start(home: String = NSHomeDirectory()): ClaudeBarCore {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    val settings = SettingsFile("${home.trimEnd('/')}/.claudebar/settings.json")
    val hookSettings = FileHookSettings(settings)
    val sessions = SessionMonitor()
    val alerts = UserNotificationsAlertSender()
    val tracking = SessionTracking(
        sessions = sessions,
        receiver = HookHttpServer(PortDiscovery.inHome(home), defaultPort = hookSettings.hookPort()),
        liveness = SystemProcessLiveness(),
        announcer = SessionAnnouncer { title, body, category -> alerts.send(title, body, category) },
        now = { NSDate().timeIntervalSince1970 },
        scope = scope,
    )
    return ClaudeBarCore(
        sessions = sessions,
        sessionTracking = tracking,
        hookSettings = hookSettings,
        hookInstaller = HookInstaller.inHome(home),
        revisions = listOf(sessions.revision),
        scope = scope,
    )
}
