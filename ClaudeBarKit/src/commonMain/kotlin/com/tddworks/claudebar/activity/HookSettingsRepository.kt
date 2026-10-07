package com.tddworks.claudebar.activity

internal object HookConstants {
    /** The hook HTTP server's port. */
    const val DEFAULT_PORT: Int = 19847

    /**
     * Set on the `claude` runs ClaudeBar spawns itself (quota refreshes). The installed hook
     * exits without posting when it sees it, so a background poll can't loop back as a
     * session (#222).
     */
    const val PROBE_ENVIRONMENT_KEY: String = "CLAUDEBAR_PROBE"

    /**
     * The header the installed hook sends with Claude Code's process ID (exported to hooks
     * as `CLAUDE_PID`), so a session whose process died without `SessionEnd` can be noticed.
     */
    const val PROCESS_ID_HEADER: String = "X-ClaudeBar-Pid"
}

/** The hook settings. Hooks are a destination, not a provider, so they stand beside the provider settings. */
internal interface HookSettingsRepository {
    fun isHookEnabled(): Boolean

    fun setHookEnabled(enabled: Boolean)

    /** The hook HTTP server's port (0 = auto-assign). */
    fun hookPort(): Int

    fun setHookPort(port: Int)
}
