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

/** The hook settings in settings.json, under the keys earlier versions wrote: `hook.enabled`, `hook.port`. */
internal class FileHookSettings(private val file: com.tddworks.claudebar.storage.SettingsFile) : HookSettingsRepository {
    override fun isHookEnabled(): Boolean =
        (file.read("hook.enabled") as? kotlinx.serialization.json.JsonPrimitive)?.content?.toBooleanStrictOrNull() ?: false

    override fun setHookEnabled(enabled: Boolean) = file.write("hook.enabled", kotlinx.serialization.json.JsonPrimitive(enabled))

    /** A missing, zero or negative port falls back to the default. */
    override fun hookPort(): Int {
        val port = (file.read("hook.port") as? kotlinx.serialization.json.JsonPrimitive)?.content?.toDoubleOrNull()?.toInt()
        return port?.takeIf { it > 0 } ?: HookConstants.DEFAULT_PORT
    }

    override fun setHookPort(port: Int) = file.write("hook.port", kotlinx.serialization.json.JsonPrimitive(port))
}
