package com.tddworks.claudebar.datasources

import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File

/**
 * *Which file on disk* has one owner (ENGINE_DESIGN §2.9): a `*` stands for part of one folder
 * name, a path may be a list, and of every match the most recently changed file is the one read.
 */
class PathPatternTest {
    @TempDir
    lateinit var home: File

    /** A file under home, last changed [ago] seconds before now. */
    private fun write(relative: String, ago: Long = 0): String {
        val file = File(home, relative)
        file.parentFile.mkdirs()
        file.writeText("{}")
        file.setLastModified(System.currentTimeMillis() - ago * 1000)
        return file.path
    }

    private fun resolve(vararg places: String) = Paths.resolve(PathPattern(places.toList()), home.path) { null }

    @Test
    fun `should read the most recently changed file a star matches`() {
        write("JetBrains/PyCharm2025.2/options/quota.xml", ago = 3600)
        val newest = write("JetBrains/IntelliJIdea2025.3/options/quota.xml", ago = 60)
        write("JetBrains/WebStorm2024.1/options/quota.xml", ago = 86400)
        assertEquals(newest, resolve("~/JetBrains/*/options/quota.xml"))
    }

    @Test
    fun `should read the newest match across every place a list names`() {
        write("JetBrains/IntelliJIdea2025.3/options/quota.xml", ago = 3600)
        val newest = write("Google/AndroidStudio2025.1/options/quota.xml", ago = 10)
        assertEquals(newest, resolve("~/JetBrains/*/options/quota.xml", "~/Google/*/options/quota.xml"))
    }

    @Test
    fun `should match a star within one folder name only`() {
        write("JetBrains/IntelliJIdea2025.3/nested/options/quota.xml")
        assertFalse(File(resolve("~/JetBrains/*/options/quota.xml")).exists())
    }

    @Test
    fun `should match part of a folder name`() {
        val idea = write("JetBrains/IntelliJIdea2025.3/options/quota.xml", ago = 3600)
        write("JetBrains/PyCharm2025.2/options/quota.xml", ago = 10)
        assertEquals(idea, resolve("~/JetBrains/IntelliJ*/options/quota.xml"))
    }

    @Test
    fun `should mean what it always meant when a path has no star`() {
        assertEquals("${home.path}/.grok/auth.json", resolve("~/.grok/auth.json"))
        assertEquals("/etc/hosts", resolve("/etc/hosts"))
    }

    @Test
    fun `should take the newest of a list of plain paths that exist`() {
        write("a/auth.json", ago = 3600)
        val b = write("b/auth.json", ago = 10)
        assertEquals(b, resolve("~/a/auth.json", "~/b/auth.json", "~/c/auth.json"))
    }

    @Test
    fun `should fill a variable or its default before the home folder`() {
        assertEquals("/opt/claude/x.json", Paths.expand("\${CLAUDE_HOME:-~/.claude}/x.json", home.path) { "/opt/claude" })
        assertEquals("${home.path}/.claude/x.json", Paths.expand("\${CLAUDE_HOME:-~/.claude}/x.json", home.path) { "" })
    }

    @Test
    fun `should decode a path as one string or a list, and write it back the same way`() {
        val one = PathPattern.from(Json.parseToJsonElement("\"~/a.json\""))
        val many = PathPattern.from(Json.parseToJsonElement("""["~/a/*.json","~/b.json"]"""))
        assertEquals(listOf("~/a.json"), one.places)
        assertEquals(listOf("~/a/*.json", "~/b.json"), many.places)
        assertEquals("\"~/a.json\"", one.toJson().toString())
        assertEquals(many, PathPattern.from(many.toJson()))
    }
}
