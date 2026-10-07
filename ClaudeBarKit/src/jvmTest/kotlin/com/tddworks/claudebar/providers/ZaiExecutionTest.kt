package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.AnsweringNetwork
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.datasources.freshFolder
import com.tddworks.claudebar.datasources.process.InMemoryLoginFolders
import com.tddworks.claudebar.datasources.testDataSources
import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageError
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.CsvSource
import org.junit.jupiter.params.provider.ValueSource
import java.io.File
import java.net.URI

/**
 * Z.ai on stubbed connections: the key comes from Settings, Claude Code's own settings file (only
 * when it points at a Z.ai host), or an environment variable, and the host comes with it.
 */
class ZaiExecutionTest {
    private val body = """{"data":{"limits":[{"type":"TOKENS_LIMIT","unit":3,"percentage":13},{"type":"TOKENS_LIMIT","unit":6,"percentage":46},{"type":"TIME_LIMIT","unit":5,"percentage":1}]}}"""

    /** The host and key of the last request Z.ai answered. */
    private class Seen {
        @Volatile var host: String? = null
        @Volatile var key: String? = null
    }

    /** Answers on the quota path, with a 10-second timeout and English, only; anything else is a 400. */
    private fun make(
        config: String? = null, platform: String? = null, envVar: String? = null,
        vault: MemoryVault = MemoryVault(), environment: Map<String, String> = emptyMap(),
        loginShell: Map<String, String> = emptyMap(), status: Int = 200, seen: Seen = Seen(),
    ): Provider {
        val home = freshFolder("zai")
        if (config != null) {
            File(home, ".claude").mkdirs()
            File(home, ".claude/settings.json").writeText(config)
        }
        val network = AnsweringNetwork { call ->
            val url = URI(call.url)
            if (url.path != "/api/monitor/usage/quota/limit" || call.timeoutSeconds != 10.0 || call.headers["Accept-Language"] != "en-US,en") {
                Response(400, body = ByteArray(0))
            } else {
                seen.host = url.host
                seen.key = call.headers["Authorization"]
                Response(status, body = body.encodeToByteArray())
            }
        }
        val settings = InMemoryProviderSettings()
        settings.setValue(platform, "platform", "zai")
        settings.setValue(envVar, "glmAuthEnvVar", "zai")
        val definition = TestDefinitions.builtIn("zai")
        val connections = testDataSources(
            network = network, environment = environment, home = home.path,
            loginShell = { loginShell[it] }, now = { System.currentTimeMillis() / 1000.0 },
        )
        return Provider(
            definition = definition,
            settings = settings,
            makeDataSource = { source, login -> connections.make(source, definition.id, vault.scoped(login), TestDefinitions.builtIns::script) },
            folders = InMemoryLoginFolders(),
            vault = vault,
            paths = HomePaths(home.path),
            isExecutable = { true },
            locate = { it },
        )
    }


    private fun RefreshOutcome.failure(): UsageError {
        assertTrue(this is RefreshOutcome.Failed, "expected a failure, got $this")
        return (this as RefreshOutcome.Failed).error
    }

    @Test
    fun `should show Z_ai, on, with its subscription page as the dashboard`() {
        val provider = make()
        assertEquals("Z.ai", provider.name)
        assertTrue(provider.defaultAccount.isEnabled)
        assertEquals("https://z.ai/subscribe", provider.plainDashboardURL)
    }

    @Test
    fun `should show the session, weekly and MCP quotas from api_z_ai when the key is saved in Settings`() {
        val seen = Seen()
        val quotas = make(vault = MemoryVault(mapOf("zai.apiKey" to "saved")), seen = seen).refreshPlain().usage().quotas
        assertEquals(listOf(QuotaType.Session, QuotaType.Weekly, QuotaType.TimeLimit("MCP")), quotas.map { it.quotaType })
        assertEquals(18000.0, quotas[0].window?.lengthSeconds)
        assertEquals(604800.0, quotas[1].window?.lengthSeconds)
        assertNull(quotas[2].window?.lengthSeconds)
        assertEquals("api.z.ai", seen.host)
        assertEquals("Bearer saved", seen.key)
    }

    @ParameterizedTest
    @CsvSource("zhipu, open.bigmodel.cn", "dev, dev.bigmodel.cn")
    fun `should ask the chosen platform's host with the saved key`(platform: String, host: String) {
        val seen = Seen()
        make(platform = platform, vault = MemoryVault(mapOf("zai.apiKey" to "saved")), seen = seen).refreshPlain().usage()
        assertEquals(host, seen.host)
    }

    @Test
    fun `should use Claude Code's key and host when Claude Code's settings point at Z_ai`() {
        val seen = Seen()
        val config = """{"env":{"ANTHROPIC_AUTH_TOKEN":"from-config","ANTHROPIC_BASE_URL":"https://open.bigmodel.cn/api/anthropic"}}"""
        make(config = config, seen = seen).refreshPlain().usage()
        assertEquals("open.bigmodel.cn", seen.host)
        assertEquals("Bearer from-config", seen.key)
    }

    @Test
    fun `should use a Z_ai provider entry from Claude Code's settings`() {
        val seen = Seen()
        val config = """{"providers":[{"api_key":"from-provider","base_url":"https://api.z.ai/api/anthropic"}]}"""
        make(config = config, seen = seen).refreshPlain().usage()
        assertEquals("api.z.ai", seen.host)
        assertEquals("Bearer from-provider", seen.key)
    }

    @Test
    fun `should never send Claude Code's key to Z_ai when Claude Code's settings point elsewhere`() {
        val seen = Seen()
        val config = """{"env":{"ANTHROPIC_AUTH_TOKEN":"anthropic-key","ANTHROPIC_BASE_URL":"https://api.anthropic.com"}}"""
        make(config = config, seen = seen).refreshPlain().failure()
        assertNull(seen.key)
    }

    @Test
    fun `should never send the key when Claude Code points at a look-alike of Z_ai's host`() {
        val seen = Seen()
        val config = """{"env":{"ANTHROPIC_AUTH_TOKEN":"key","ANTHROPIC_BASE_URL":"https://api.z.ai.example.com"}}"""
        make(config = config, seen = seen).refreshPlain().failure()
        assertNull(seen.key)
    }

    @Test
    fun `should use the key from the environment variable the person named`() {
        val seen = Seen()
        make(envVar = "MY_GLM_KEY", environment = mapOf("MY_GLM_KEY" to "from-env"), seen = seen).refreshPlain().usage()
        assertEquals("Bearer from-env", seen.key)
        assertEquals("api.z.ai", seen.host)
    }

    @Test
    fun `should find the key the person exported only in their login shell (#170)`() {
        val seen = Seen()
        make(envVar = "MY_GLM_KEY", loginShell = mapOf("MY_GLM_KEY" to "from-shell"), seen = seen).refreshPlain().usage()
        assertEquals("Bearer from-shell", seen.key)
    }

    @Test
    fun `should prefer the app's own environment to the login shell`() {
        val seen = Seen()
        make(environment = mapOf("ZAI_API_KEY" to "from-env"), loginShell = mapOf("ZAI_API_KEY" to "from-shell"), seen = seen).refreshPlain().usage()
        assertEquals("Bearer from-env", seen.key)
    }

    @Test
    fun `should use ZAI_API_KEY when the person named no variable`() {
        val seen = Seen()
        make(environment = mapOf("ZAI_API_KEY" to "from-env"), seen = seen).refreshPlain().usage()
        assertEquals("Bearer from-env", seen.key)
    }

    @Test
    fun `should fail to read usage when there is no key anywhere`() {
        make().refreshPlain().failure()
    }

    @Test
    fun `should use an added login's own key and platform, never the environment`() {
        val seen = Seen()
        val vault = MemoryVault()
        val provider = make(vault = vault, environment = mapOf("ZAI_API_KEY" to "from-env"), seen = seen)
        val work = provider.accounts.add(filling = mapOf("apiKey" to "work", "platform" to "zhipu")).done()
        provider.refreshNow(work).usage()
        assertEquals("Bearer work", seen.key)
        assertEquals("open.bigmodel.cn", seen.host)
        vault.secrets.remove("${work.id}.apiKey")
        provider.refreshNow(work).failure()
    }

    @ParameterizedTest
    @ValueSource(ints = [401, 403])
    fun `should ask to sign in again when Z_ai refuses the key`(code: Int) {
        val failure = make(vault = MemoryVault(mapOf("zai.apiKey" to "saved")), status = code).refreshPlain().failure()
        assertEquals(UsageError.AuthenticationRequired, failure)
    }
}
