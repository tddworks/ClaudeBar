package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.DefinitionError
import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows

/**
 * A setting's kind owns its rule; a choice's options carry their values. How an added login's
 * folder is checked against the others' (`DefaultPathIsolationTests`) runs through `Provider`,
 * and is the lifecycle's to test.
 */
class SettingTest {
    private fun decode(json: String) = Setting.from(Json.parseToJsonElement(json))

    private val region = """
        {"id":"region","label":"Region","scope":"account","default":"china",
         "kind":{"choice":[{"id":"china","label":"China","site":"acme.cn"},{"id":"international","label":"International","site":"acme.com"}]}}
    """.trimIndent()

    @Test
    fun `should fill in the chosen option and every value it carries`() {
        assertEquals(mapOf("region" to "international", "region.site" to "acme.com"), decode(region).fills("international"))
    }

    @Test
    fun `should use the default for a blank, or the first option when a choice has no default`() {
        assertEquals("china", decode(region).value("  "))
        val noDefault = decode("""{"id":"plan","label":"Plan","kind":{"choice":["pro","max"]}}""")
        assertEquals("pro", noDefault.value(null))
        assertEquals("max", noDefault.value(" max "))
    }

    @Test
    fun `should never fill a key into a request except by looking it up`() {
        val key = decode("""{"id":"apiKey","label":"API key","kind":"secret"}""")
        assertTrue(key.fills("sk-1").isEmpty())
    }

    @Test
    fun `should refuse a key that comes with a default`() {
        assertThrows<DefinitionError> { decode("""{"id":"apiKey","label":"API key","kind":"secret","default":"sk-0"}""") }
    }

    @Test
    fun `should still read settings written in the older form`() {
        assertEquals(Setting.Kind.Secret, decode("""{"id":"apiKey","label":"API key","secret":true}""").kind)
        assertEquals(
            Setting.Kind.Choice(listOf(Setting.Option("a"), Setting.Option("b"))),
            decode("""{"id":"region","label":"Region","choices":["a","b"]}""").kind,
        )
    }

    @Test
    fun `should say what is wrong with a choice, text or folder the person entered`() {
        val paths = FakePaths(folders = setOf("/Users/me/.acme-work"))
        assertEquals("Choose a Region from the list.", decode(region).check("mars", paths))
        assertNull(decode(region).check("china", paths))
        val profile = decode("""{"id":"profile","label":"Profile","kind":{"text":{"pattern":"^[a-z]+$"}}}""")
        assertEquals("Enter a valid Profile.", profile.check("Work 1", paths))
        val folder = decode("""{"id":"home","label":"CLI data folder","kind":{"path":{"mustExist":true}}}""")
        assertEquals("Enter a full path for CLI data folder.", folder.check("relative/dir", paths))
        assertEquals("Choose an existing folder for CLI data folder.", folder.check("/Users/me/missing", paths))
        assertNull(folder.check("/Users/me/.acme-work", paths))
        assertEquals("Fill in CLI data folder.", folder.check("", paths))
    }

    @Test
    fun `should expand path defaults before checking their location and existence`() {
        val folder = decode("""{"id":"home","label":"Folder","kind":{"path":{"mustExist":true}}}""")
        val paths = FakePaths(
            folders = setOf("/Users/me/work"),
            aliases = mapOf(
                "\${ACME_HOME:-~/work}" to "/Users/me/work", "\${MISSING}" to "/Users/me/missing",
                "\${RELATIVE}" to "relative/work",
            ),
        )
        assertNull(folder.check("\${ACME_HOME:-~/work}", paths))
        assertEquals("Choose an existing folder for Folder.", folder.check("\${MISSING}", paths))
        assertEquals("Enter a full path for Folder.", folder.check("\${RELATIVE}", paths))
        assertEquals("Enter a full path for Folder.", folder.check("\${UNSET}", paths))
    }

    @Test
    fun `should find a login's folder among its values, and no folder for a choice`() {
        val folder = decode("""{"id":"home","label":"Folder","scope":"account","kind":"path"}""")
        assertEquals("/Users/me/work", folder.path(mapOf("home" to "/Users/me/work")))
        assertNull(decode(region).path(mapOf("region" to "china")))
    }

    @Test
    fun `should treat two spellings of one folder as the same place, but never two equal choices`() {
        val paths = FakePaths(folders = emptySet(), aliases = mapOf("~/.acme" to "/Users/me/.acme"))
        val folder = decode("""{"id":"home","label":"Folder","kind":"path"}""")
        assertTrue(folder.isSamePlace("~/.acme", "/Users/me/.acme", paths))
        assertFalse(decode(region).isSamePlace("china", "china", paths))
    }

    @Test
    fun `should keep a setting as written when it is saved and read back`() {
        val setting = decode(region)
        assertEquals(setting, Setting.from(Json.parseToJsonElement(setting.toJson().toString())))
    }
}

/** The file system as a test needs it: these folders exist, and these spellings are the same place. */
internal class FakePaths(private val folders: Set<String>, private val aliases: Map<String, String> = emptyMap()) : PathChecking {
    override fun expanded(path: String): String = aliases[path] ?: path
    override fun isFolder(path: String): Boolean = canonical(path) in folders
    override fun canonical(path: String): String = aliases[path] ?: path
}
