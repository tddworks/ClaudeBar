package com.tddworks.claudebar.activity

import kotlinx.coroutines.flow.Flow

/** Where Claude Code's hook events arrive — the hook HTTP server, or a test's fake. */
internal interface HookEventReceiver {
    /** Starts listening; the flow ends when the receiver stops or fails, and stops it when its collector leaves. */
    suspend fun start(): Flow<SessionEvent>

    suspend fun stop()
}
