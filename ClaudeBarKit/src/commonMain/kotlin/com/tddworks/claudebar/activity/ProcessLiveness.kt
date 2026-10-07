package com.tddworks.claudebar.activity

/**
 * Whether a process still runs on this Mac. A Claude Code session killed outright (a crash,
 * a force-quit terminal) never sends `SessionEnd`; this is how [SessionMonitor] finds out.
 */
internal fun interface ProcessLiveness {
    fun isRunning(processId: Int): Boolean
}
