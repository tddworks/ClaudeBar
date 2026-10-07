package com.tddworks.claudebar.activity

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** Reads a Claude Code hook payload (`session_id`, `hook_event_name`, `cwd`, …) into a [SessionEvent]. */
internal object SessionEventParser {
    /**
     * The event, or null for a payload that isn't JSON, names no session or event, or names
     * an event ClaudeBar doesn't know. [processId] is the hook's `X-ClaudeBar-Pid` header:
     * Claude Code's process ID, or empty when the hook had none.
     */
    fun parse(body: String, receivedAtSeconds: Double, processId: String? = null): SessionEvent? {
        val json = runCatching { Json.parseToJsonElement(body) }.getOrNull() as? JsonObject ?: return null
        val sessionId = json["session_id"].string() ?: return null
        val eventName = json["hook_event_name"].string()?.let { SessionEvent.EventName.from(it) } ?: return null
        return SessionEvent(
            sessionId = sessionId,
            eventName = eventName,
            cwd = json["cwd"].string() ?: "",
            receivedAtSeconds = receivedAtSeconds,
            // `StopFailure` carries `error`, `Notification` carries `message`; an `error` that
            // isn't text hides `message`, as it always has.
            message = (json["error"] ?: json["message"]).string(),
            processId = processId?.trim(' ', '\t')?.toIntOrNull(),
        )
    }

    private fun JsonElement?.string(): String? = (this as? JsonPrimitive)?.takeIf { it.isString }?.content
}
