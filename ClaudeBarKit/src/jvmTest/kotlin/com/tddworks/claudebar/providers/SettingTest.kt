package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.DefinitionError
import com.tddworks.claudebar.datasources.Fetch
import com.tddworks.claudebar.datasources.Paths
import kotlinx.serialization.json.Json
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.CsvSource

/** A setting's kind owns its rule; a choice's options carry their values. */
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

/** An added login's folder is never the default login's, and a saved `~` path is the absolute folder its CLI needs. */
class DefaultPathIsolationTest {
    /** `~` is `/Users/me`; every folder exists. */
    private object IsolationPaths : PathChecking {
        override fun isFolder(path: String) = true
        override fun canonical(path: String) = expanded(path)
        override fun expanded(path: String) = Paths.expand(path, "/Users/me") { null }
    }

    private val stub = StubbedProvider()

    @AfterEach
    fun cleanUp() = stub.cleanUp()

    private fun provider(id: String, accounts: List<ProviderAccountConfig> = emptyList()) =
        stub.make(TestDefinitions.builtIn(id), accounts, paths = IsolationPaths, settings = InMemoryProviderSettings())

    @ParameterizedTest
    @CsvSource("gemini, home, ~", "kiro, home, ~", "grok, directory, ~/.grok", "kimi, home, ~/.kimi")
    fun `should reject an added login that reuses the default folder`(id: String, setting: String, folder: String) {
        val account = provider(id)
        assertTrue(account.accounts.add(filling = mapOf(setting to folder)) is Outcome.Refused)
        assertEquals(1, account.accounts.size)
    }

    @Test
    fun `should restore a saved tilde path as an absolute folder`() {
        val owner = provider("kiro", listOf(ProviderAccountConfig("work", "Work", probeConfig = mapOf("home" to "~/work"), madeBy = AccountOrigin.FORM)))
        val account = owner.accounts.all.first { it.accountId == "work" }
        assertEquals("/Users/me/work", account.values["home"])
    }

    @Test
    fun `should restore a signed-in folder as the absolute path its CLI needs`() {
        val owner = provider(
            "codex",
            listOf(ProviderAccountConfig("work", "Work", probeConfig = mapOf("codexHome" to "~/work", "chatgptAccountId" to "work-id"), madeBy = AccountOrigin.FOLDER)),
        )
        val account = owner.accounts.all.first { it.accountId == "work" }
        assertEquals("/Users/me/work", account.values["codexHome"])
        val rpc = owner.dataSources(account).first { it.kind == "rpc" }
        assertEquals("/Users/me/work", (rpc.definition.fetch as Fetch.JsonRpc).call.environment.set["CODEX_HOME"])
    }

    @Test
    fun `should validate a blank path default after expansion`() {
        val owner = provider("kimi")
        owner.configuration.set("home", "/Users/me/other").done()
        val added = owner.accounts.add(filling = emptyMap()).done()
        assertEquals("/Users/me/.kimi", added.values["home"])
    }

    @Test
    fun `should reject a blank default that duplicates another login folder`() {
        val owner = provider("kimi")
        assertEquals(
            Outcome.Refused("Choose a separate folder for Signed-in Kimi Folder — another Kimi login uses this one."),
            owner.accounts.add(filling = emptyMap()),
        )
    }

    @Test
    fun `should save a tilde path as the absolute folder the CLI needs`() {
        val owner = provider("kiro")
        val account = owner.accounts.add(filling = mapOf("home" to "~/work")).done()
        assertEquals("/Users/me/work", account.values["home"])
    }
}
