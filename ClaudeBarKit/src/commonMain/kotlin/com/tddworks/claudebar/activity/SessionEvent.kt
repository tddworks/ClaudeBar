package com.tddworks.claudebar.activity

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** One hook event from Claude Code, as its hook system names it. */
@Serializable
internal data class SessionEvent(
    val sessionId: String,
    val eventName: EventName,
    /** The folder Claude Code runs in; empty when the hook didn't say. */
    val cwd: String,
    val receivedAtSeconds: Double,
    /**
     * What the event is about, when the hook says: what `Notification` is blocked on
     * ("Claude needs your permission to use Bash"), what a `StopFailure` failed with.
     */
    val message: String? = null,
    /** The Claude Code process the event came from, so a session killed without `SessionEnd` can be noticed. */
    val processId: Int? = null,
) {
    /**
     * Whether this is ClaudeBar's own background run, to be ignored: quota refreshes run
     * `claude /usage` in `<AppSupport>/ClaudeBar/Probe` and its hooks loop back here (#172).
     * An event with no folder is dropped too (#222): it can't be told from that run and
     * couldn't name a project anyway. The first defence is upstream: those runs carry
     * `CLAUDEBAR_PROBE=1`, and the installed hook exits before posting.
     */
    val isClaudeBarProbe: Boolean
        get() = cwd.isBlank() || standardizedPathComponents(cwd).takeLast(2) == listOf("ClaudeBar", "Probe")

    @Serializable
    enum class EventName(val rawValue: String) {
        @SerialName("SessionStart") SESSION_START("SessionStart"),
        @SerialName("SessionEnd") SESSION_END("SessionEnd"),
        @SerialName("TaskCompleted") TASK_COMPLETED("TaskCompleted"),
        @SerialName("SubagentStart") SUBAGENT_START("SubagentStart"),
        @SerialName("SubagentStop") SUBAGENT_STOP("SubagentStop"),
        @SerialName("Stop") STOP("Stop"),
        /** Fires instead of `Stop` when the turn ends in an error (a connection lost while the Mac slept). */
        @SerialName("StopFailure") STOP_FAILURE("StopFailure"),
        /** The start of every turn: revives a session out of `STOPPED`. */
        @SerialName("UserPromptSubmit") USER_PROMPT_SUBMIT("UserPromptSubmit"),
        /** Claude Code needs the person, most importantly for a permission prompt. */
        @SerialName("Notification") NOTIFICATION("Notification");

        companion object {
            /** The event Claude Code's hooks call [rawValue], or null for one ClaudeBar doesn't know. */
            fun from(rawValue: String): EventName? = entries.firstOrNull { it.rawValue == rawValue }
        }
    }
}

/**
 * A path's components as Foundation's `standardizingPath` then `pathComponents` give them:
 * no empty or `.` parts, `..` resolved in an absolute path, `/` first when absolute.
 */
internal fun standardizedPathComponents(path: String): List<String> {
    val absolute = path.startsWith("/")
    val parts = mutableListOf<String>()
    for (part in path.split('/')) {
        when {
            part.isEmpty() || part == "." -> Unit
            part == ".." && absolute -> parts.removeLastOrNull()
            else -> parts += part
        }
    }
    return if (absolute) listOf("/") + parts else parts
}

/** The last component of the standardized path: `/a/b/` → `b`, `/` → `/`, `` → ``. */
internal fun lastPathComponent(path: String): String = standardizedPathComponents(path).lastOrNull() ?: ""
