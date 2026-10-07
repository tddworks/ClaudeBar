package com.tddworks.claudebar.kit

import com.tddworks.claudebar.activity.HookInstaller
import com.tddworks.claudebar.activity.HookSettingsRepository
import com.tddworks.claudebar.activity.SessionMonitor
import com.tddworks.claudebar.activity.SessionTracking
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * The composition root (MODULAR_DESIGN §1): every context built once and wired, and the one
 * change signal the UI observes (§5). The App starts it and shows its state; nothing in Kotlin
 * reaches back to the App. Contexts join as they switch over (§8).
 */
public class ClaudeBarCore internal constructor(
    /** Claude Code's sessions, from its hooks. */
    public val sessions: SessionMonitor,
    /** The hook loop: on while hooks are on. */
    public val sessionTracking: SessionTracking,
    public val hookSettings: HookSettingsRepository,
    public val hookInstaller: HookInstaller,
    revisions: List<StateFlow<Long>>,
    scope: CoroutineScope,
) {
    private val counter = MutableStateFlow(0L)

    /** Moves whenever anything the UI shows changes — one signal for the whole kit. */
    public val changes: StateFlow<Long> = counter.asStateFlow()

    init {
        for (revision in revisions) {
            scope.launch { revision.drop(1).collect { counter.update { it + 1 } } }
        }
    }

    public companion object
}
