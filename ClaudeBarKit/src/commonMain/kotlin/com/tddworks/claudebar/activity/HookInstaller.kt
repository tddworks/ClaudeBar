package com.tddworks.claudebar.activity

import kotlinx.io.buffered
import kotlinx.io.files.Path
import kotlinx.io.files.SystemFileSystem
import kotlinx.io.readString
import kotlinx.io.writeString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Turns ClaudeBar's hook on and off in Claude Code's `~/.claude/settings.json`, keeping the
 * person's settings and other tools' hooks. ClaudeBar's entries are known by [HOOK_MARKER].
 */
public class HookInstaller internal constructor(internal val settingsPath: String) {
    private val file = Path(settingsPath)

    /** Thrown when Claude Code's settings can't be read: they are left for the person to fix. */
    internal class CorruptedSettingsFile(message: String) : Exception(message)

    /**
     * Turns the hook on or off: null when done, else why it couldn't — the outcome Swift reads,
     * since an exception never crosses the bridge.
     */
    public fun turn(on: Boolean): String? = runCatching { if (on) install() else uninstall() }
        .exceptionOrNull()?.let { it.message ?: it.toString() }

    /**
     * Adds the hook to every event in [HOOK_EVENTS], replacing ClaudeBar's earlier entry, in
     * the matcher format: `{"SessionStart": [{"matcher": ".*", "hooks": [{"type": "command", "command": "…"}]}]}`.
     * Creates the file and its folder when missing.
     */
    internal fun install() {
        val settings = readOrCreateSettings().toMutableMap()
        val hooks = (settings["hooks"] as? JsonObject ?: JsonObject(emptyMap())).toMutableMap()
        for (event in HOOK_EVENTS) {
            val entries = matcherEntries(hooks[event]).orEmpty().filterNot { containsOurHook(it) }
            hooks[event] = JsonArray(entries + ourEntry)
        }
        settings["hooks"] = JsonObject(hooks)
        writeSettings(JsonObject(settings))
    }

    /** Removes only ClaudeBar's entries, dropping events and a `hooks` section left empty. */
    internal fun uninstall() {
        val settings = runCatching { readOrCreateSettings() }.getOrNull()?.toMutableMap() ?: return
        val hooks = (settings["hooks"] as? JsonObject)?.toMutableMap() ?: return
        for (event in HOOK_EVENTS) {
            val entries = matcherEntries(hooks[event])?.filterNot { containsOurHook(it) } ?: continue
            if (entries.isEmpty()) hooks.remove(event) else hooks[event] = JsonArray(entries)
        }
        if (hooks.isEmpty()) settings.remove("hooks") else settings["hooks"] = JsonObject(hooks)
        writeSettings(JsonObject(settings))
    }

    /** Whether any event carries ClaudeBar's hook; false for a missing or unreadable file. */
    fun isInstalled(): Boolean {
        val settings = runCatching { readOrCreateSettings() }.getOrNull() ?: return false
        val hooks = settings["hooks"] as? JsonObject ?: return false
        return hooks.values.any { value -> matcherEntries(value)?.any { containsOurHook(it) } ?: false }
    }

    /** A list of matcher entries, or null when [value] isn't one (as Foundation's `[[String: Any]]` cast). */
    private fun matcherEntries(value: JsonElement?): List<JsonObject>? =
        (value as? JsonArray)?.takeIf { array -> array.all { it is JsonObject } }?.map { it as JsonObject }

    private fun containsOurHook(entry: JsonObject): Boolean =
        matcherEntries(entry["hooks"])?.any { hook ->
            (hook["command"] as? JsonPrimitive)?.takeIf { it.isString }?.content?.contains(HOOK_MARKER) ?: false
        } ?: false

    private val ourEntry = JsonObject(
        mapOf(
            "matcher" to JsonPrimitive(".*"),
            "hooks" to JsonArray(
                listOf(JsonObject(mapOf("type" to JsonPrimitive("command"), "command" to JsonPrimitive(HOOK_COMMAND)))),
            ),
        ),
    )

    /** No file, or an empty one, is no settings; anything else that isn't a JSON object throws. */
    private fun readOrCreateSettings(): JsonObject {
        if (!SystemFileSystem.exists(file)) return JsonObject(emptyMap())
        val text = runCatching { SystemFileSystem.source(file).buffered().use { it.readString() } }.getOrNull()
        if (text.isNullOrEmpty()) return JsonObject(emptyMap())
        return runCatching { Json.parseToJsonElement(text) }.getOrNull() as? JsonObject
            ?: throw CorruptedSettingsFile(
                "Failed to parse $settingsPath — file may be corrupted. Fix it manually before retrying.",
            )
    }

    private fun writeSettings(settings: JsonObject) {
        file.parent?.let { SystemFileSystem.createDirectories(it) }
        val temporary = Path("$settingsPath.writing")
        SystemFileSystem.sink(temporary).buffered().use { it.writeString(pretty(settings, "")) }
        SystemFileSystem.atomicMove(temporary, file)
    }

    /** Two-space indents and sorted names, as Foundation's pretty-printed, sorted-keys JSON. */
    private fun pretty(element: JsonElement, indent: String): String {
        val inner = "$indent  "
        return when (element) {
            is JsonObject -> if (element.isEmpty()) "{}" else element.entries.sortedBy { it.key }
                .joinToString(",\n", "{\n", "\n$indent}") { (name, value) ->
                    "$inner${JsonPrimitive(name)} : ${pretty(value, inner)}"
                }
            is JsonArray -> if (element.isEmpty()) "[]" else element
                .joinToString(",\n", "[\n", "\n$indent]") { "$inner${pretty(it, inner)}" }
            else -> element.toString()
        }
    }

    companion object {
        /** The shell function name that marks ClaudeBar's hook command. */
        const val HOOK_MARKER: String = "__claudebar_hook"

        /**
         * The hook command; it reads the port from [PortDiscovery]'s file at run time. Runs
         * ClaudeBar spawns itself carry `CLAUDEBAR_PROBE=1`, so the guard returns before the
         * POST (#222). Claude Code exports its process ID to hooks as `CLAUDE_PID`; the POST
         * sends it in a header so ClaudeBar notices when the process is gone.
         */
        const val HOOK_COMMAND: String =
            "__claudebar_hook() { [ \"\$${HookConstants.PROBE_ENVIRONMENT_KEY}\" = \"1\" ] && return 0; " +
                "PORT=\$(cat \"\$HOME/.claude/claudebar-hook-port\" 2>/dev/null || echo ${HookConstants.DEFAULT_PORT}); " +
                "cat | curl -s -X POST \"http://localhost:\${PORT}/hook\" -H 'Content-Type: application/json' " +
                "-H \"${HookConstants.PROCESS_ID_HEADER}: \$CLAUDE_PID\" -d @- > /dev/null 2>&1 & }; __claudebar_hook"

        /** The events the hook is registered for. */
        val HOOK_EVENTS: List<String> = listOf(
            "SessionStart",
            "SessionEnd",
            "TaskCompleted",
            "SubagentStart",
            "SubagentStop",
            "Stop",
            "StopFailure",
            "UserPromptSubmit",
        )

        /** Claude Code's settings under [home]. */
        fun inHome(home: String): HookInstaller = HookInstaller("${home.trimEnd('/')}/.claude/settings.json")
    }
}
