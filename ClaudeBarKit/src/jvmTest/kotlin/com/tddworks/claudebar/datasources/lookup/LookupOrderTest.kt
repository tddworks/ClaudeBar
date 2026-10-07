package com.tddworks.claudebar.datasources.lookup

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/** *KEY LOOKUP ORDER* — where a data source looks for its key, in order, as the person would recognise it. Never a value. */
class LookupOrderTest {
    @Test
    fun `should name each place a key is looked for the way a person would find it, with the sign-in hint`() {
        val order = lookup("""
        { "firstOf": [
            { "jsonFile": { "path": "~/.claude/.credentials.json", "token": "$.claudeAiOauth.accessToken" } },
            { "keychain": { "service": "Claude Code-credentials", "token": "$.claudeAiOauth.accessToken" } },
            { "environment": "CLAUDE_CODE_OAUTH_TOKEN" }
          ],
          "refresh": { "oauth2": { "tokenURL": "https://example.com/token", "clientId": "x",
                                   "hint": "Run `claude` in terminal to log in again." } } }
        """)

        assertEquals(
            listOf("~/.claude/.credentials.json", "Keychain “Claude Code-credentials”", "${'$'}CLAUDE_CODE_OAUTH_TOKEN"),
            order.lookupOrder,
        )
        assertEquals("Run `claude` in terminal to log in again.", order.hint)
    }

    @Test
    fun `should name a single place to look with no hint`() {
        val order = lookup("""{ "environment": "DEEPSEEK_API_KEY" }""")

        assertEquals(listOf("${'$'}DEEPSEEK_API_KEY"), order.lookupOrder)
        assertNull(order.hint)
    }
}
