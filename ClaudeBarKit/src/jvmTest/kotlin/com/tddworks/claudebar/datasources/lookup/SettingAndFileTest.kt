package com.tddworks.claudebar.datasources.lookup

import com.tddworks.claudebar.datasources.DataSourceError
import com.tddworks.claudebar.datasources.Template
import com.tddworks.claudebar.datasources.definition
import com.tddworks.claudebar.datasources.freshFolder
import com.tddworks.claudebar.datasources.testDataSources
import com.tddworks.claudebar.datasources.thrown
import com.tddworks.claudebar.quotas.QuotaType
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

/**
 * Two cases *Add Provider* needs: a key the person pasted into ClaudeBar (`setting`, kept in its
 * vault, never in a file), and a usage file on disk (`file`) — *Start from: API · File*.
 */
class SettingAndFileTest {
    private val api = lookup("""{ "setting": "apiKey" }""")

    private fun reader(vault: FakeVault) = CredentialFinders(
        providerId = "openrouter", home = "/nowhere", environment = { null }, security = FakeSecurity { SecurityResult(1, "") },
        secrets = vault, database = FakeDatabase { _, _ -> emptyList() }, browserCookies = FakeCookies(), browserStorage = FakeStorage(),
    ).reader(api)

    @Test
    fun `should send the key the person saved in ClaudeBar as the definition says`() {
        val credential = reader(FakeVault(mapOf("openrouter.apiKey" to "sk-or-1"))).find()?.credential

        assertEquals("Bearer sk-or-1", Template.fill("Bearer {{token}}", credential))
    }

    @Test
    fun `should ask for a key at the lookup step when none is saved`() {
        assertNull(reader(FakeVault()).find())
    }

    @Test
    fun `should name where the key is kept, never its value, when it is saved in ClaudeBar`() {
        assertEquals(listOf("API key saved in ClaudeBar"), api.lookupOrder)
    }

    @Test
    fun `should show what a usage file holds`() = runTest {
        val home = freshFolder("file-fetch")
        try {
            File(home, "usage.json").writeText("""{"left":42}""")
            val source = testDataSources(home = home.path).make(definition("""
            { "kind": "file", "fetch": { "file": { "path": "~/usage.json" } },
              "mapping": { "json": { "quotas": [{ "kind": "session", "leftPercent": "$.left" }] } } }
            """), "openrouter")

            assertTrue(source.isReady())
            assertEquals(42.0, source.fetchUsage().quota(QuotaType.Session)?.percentRemaining)
        } finally {
            home.deleteRecursively()
        }
    }

    @Test
    fun `should not be ready and fail at the fetch step when the usage file is missing`() = runTest {
        val source = testDataSources().make(definition("""
        { "kind": "file", "fetch": { "file": { "path": "/nonexistent/usage.json" } }, "mapping": { "json": { "quotas": [] } } }
        """), "openrouter")

        assertFalse(source.isReady())
        assertEquals(DataSourceError.Step.FETCH, (thrown { source.fetchResponse() } as? DataSourceError)?.step)
    }
}
