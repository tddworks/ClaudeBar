package com.tddworks.claudebar.activity

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import org.junit.jupiter.api.io.TempDir
import java.io.File

class HookInstallerTest {
    private val command = HookInstaller.HOOK_COMMAND

    @Test
    fun `should carry ClaudeBar's marker so the installed hook can be recognised as ClaudeBar's`() {
        assertTrue(command.contains(HookInstaller.HOOK_MARKER))
    }

    @Test
    fun `should send each Claude Code event to ClaudeBar on this Mac`() {
        assertTrue(command.contains("curl"))
        assertTrue(command.contains("POST"))
        assertTrue(command.contains("localhost"))
        assertTrue(command.contains("/hook"))
    }

    @Test
    fun `should tell ClaudeBar which Claude Code process sent the event, so it can notice when it is gone`() {
        assertTrue(command.contains("-H \"${HookConstants.PROCESS_ID_HEADER}: \$CLAUDE_PID\""))
    }

    @Test
    fun `should find ClaudeBar's port in the file ClaudeBar leaves for it`() {
        assertTrue(command.contains("claudebar-hook-port"))
    }

    @Test
    fun `should listen to the eight session events Claude Code reports`() {
        val events = HookInstaller.HOOK_EVENTS
        listOf("StopFailure", "SessionStart", "SessionEnd", "TaskCompleted", "SubagentStart", "SubagentStop", "Stop", "UserPromptSubmit")
            .forEach { assertTrue(events.contains(it), it) }
        assertEquals(8, events.size)
    }

    // Claude Code's settings file, in its own temporary folder, never the person's own.

    @TempDir
    lateinit var home: File

    private val installer get() = HookInstaller.inHome(home.path)
    private val file get() = File(installer.settingsPath)

    private fun write(json: String) {
        file.parentFile.mkdirs()
        file.writeText(json)
    }

    private fun read(): JsonObject = Json.parseToJsonElement(file.readText()).jsonObject

    private fun hooks(event: String): List<JsonObject> =
        ((read()["hooks"] as? JsonObject)?.get(event) as? JsonArray).orEmpty().map { it as JsonObject }

    private fun commands(entries: List<JsonObject>): List<String> = entries.flatMap { entry ->
        (entry["hooks"] as? JsonArray).orEmpty().mapNotNull { ((it as JsonObject)["command"] as? JsonPrimitive)?.content }
    }

    @Test
    fun `should count the hook not installed when Claude Code has no settings file`() {
        assertFalse(installer.isInstalled())
    }

    @Test
    fun `should create Claude Code's settings with the hook on every session event when there is none yet`() {
        installer.install()

        assertTrue(installer.isInstalled())
        for (event in HookInstaller.HOOK_EVENTS) {
            assertEquals(listOf(command), commands(hooks(event)), event)
        }
    }

    @Test
    fun `should keep the person's own settings and other tools' hooks when turning the hook on`() {
        write("""{"model":"opus","hooks":{"Stop":[{"matcher":".*","hooks":[{"type":"command","command":"say done"}]}]}}""")

        installer.install()

        assertEquals("opus", (read()["model"] as JsonPrimitive).content)
        assertEquals(listOf("say done", command), commands(hooks("Stop")))
    }

    @Test
    fun `should add the hook once when it is turned on twice`() {
        installer.install()
        installer.install()

        assertEquals(listOf(command), commands(hooks("SessionStart")))
    }

    @Test
    fun `should remove only ClaudeBar's hook when turning it off, leaving other tools' hooks`() {
        write("""{"hooks":{"Stop":[{"matcher":".*","hooks":[{"type":"command","command":"say done"}]}]}}""")
        installer.install()

        installer.uninstall()

        assertFalse(installer.isInstalled())
        assertEquals(listOf("say done"), commands(hooks("Stop")))
        assertNull((read()["hooks"] as? JsonObject)?.get("SessionStart"))
    }

    @Test
    fun `should leave no empty hooks section once the hook is turned off`() {
        write("""{"model":"opus"}""")
        installer.install()

        installer.uninstall()

        assertNull(read()["hooks"])
        assertEquals("opus", (read()["model"] as JsonPrimitive).content)
    }

    @Test
    fun `should refuse to change a settings file it cannot read, and leave it as it was`() {
        write("{ not json")

        assertThrows<HookInstaller.CorruptedSettingsFile> { installer.install() }
        assertEquals("{ not json", file.readText())
        assertFalse(installer.isInstalled())
    }

    @Test
    fun `should treat an empty settings file as no settings`() {
        write("")

        installer.install()

        assertTrue(installer.isInstalled())
    }

    @Test
    fun `should mark the hook with a name the shell accepts as a function name`() {
        val marker = HookInstaller.HOOK_MARKER
        assertFalse(marker.isEmpty())
        assertTrue(marker.all { it.isLetter() || it == '_' })
    }

    // Probe sessions (issue #222)

    @Test
    fun `should send nothing when the session is ClaudeBar's own Claude run (#222)`() {
        // The guard references the probe marker and returns before any POST.
        val probeGuard = command.indexOf("[ \"\$${HookConstants.PROBE_ENVIRONMENT_KEY}\" = \"1\" ] && return 0")
        assertTrue(probeGuard >= 0)
        assertTrue(probeGuard < command.indexOf("curl"))
    }

    // Kotlin only: the command is byte-for-byte the one Swift installed, so an upgrade finds it.

    @Test
    fun `should install the same hook command ClaudeBar always has`() {
        assertEquals(
            "__claudebar_hook() { [ \"\$CLAUDEBAR_PROBE\" = \"1\" ] && return 0; " +
                "PORT=\$(cat \"\$HOME/.claude/claudebar-hook-port\" 2>/dev/null || echo 19847); " +
                "cat | curl -s -X POST \"http://localhost:\${PORT}/hook\" -H 'Content-Type: application/json' " +
                "-H \"X-ClaudeBar-Pid: \$CLAUDE_PID\" -d @- > /dev/null 2>&1 & }; __claudebar_hook",
            command,
        )
    }
}
