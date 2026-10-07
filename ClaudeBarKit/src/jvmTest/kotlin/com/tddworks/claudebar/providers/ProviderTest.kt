package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.DataSourceDefinition
import com.tddworks.claudebar.datasources.DataSourceError
import com.tddworks.claudebar.datasources.HttpCall
import com.tddworks.claudebar.datasources.NetworkClient
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.datasources.process.QualityOfService
import com.tddworks.claudebar.datasources.process.currentQualityOfService
import com.tddworks.claudebar.quotas.QuotaStatus
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.net.URI
import java.util.Collections

/**
 * THE lifecycle, once for every provider — pinned on a provider no vendor ships: "Acme",
 * whose `api` falls back to a `backup` the person can switch off. Every rule here holds for
 * Claude, Codex and any provider someone adds.
 */
class ProviderTest {
    // Acme, as data

    private fun source(json: String) = DataSourceDefinition.from(Json.parseToJsonElement(json))

    /** An added login asks with its own `login` value. */
    private val loginPatch: Map<String, JsonElement> = (Json.parseToJsonElement(
        """
        { "api": { "fetch": { "http": { "url": "https://api.acme.test/usage?login={{account.login}}" } } },
          "backup": { "fetch": { "http": { "url": "https://backup.acme.test/usage?login={{account.login}}" } } } }
        """,
    ) as JsonObject)

    private fun acme(verifyBeforeBackground: Boolean = false, patch: Map<String, JsonElement> = loginPatch) = ProviderDefinition(
        profile = ProviderProfile("acme", "Acme"),
        dataSources = listOf(
            source(
                """
                { "kind": "api", "label": "API",
                  "fetch": { "http": { "url": "https://api.acme.test/usage" } },
                  "mapping": { "json": { "quotas": [ { "kind": "session", "at": "$", "usedPercent": "used" } ] } },
                  "cache": { "ttl": 600 },
                  "verifyBeforeBackground": $verifyBeforeBackground,
                  "fallback": { "to": "backup", "enabledBySetting": "backupEnabled" } }
                """,
            ),
            source(
                """
                { "kind": "backup", "label": "Backup",
                  "fetch": { "http": { "url": "https://backup.acme.test/usage" } },
                  "mapping": { "json": { "quotas": [ { "kind": "session", "at": "$", "usedPercent": "used" } ] } } }
                """,
            ),
        ),
        defaultDataSource = "api",
        accounts = ProviderDefinition.Accounts(patch = patch),
    )

    /** The network Acme talks to: each host answers what it was told, and every request is remembered — a fake, so an answer can be held back. */
    private class AcmeNetwork : NetworkClient {
        private val answers = mutableMapOf<String, Pair<Int, String>>()
        private val asked = mutableListOf<String>()

        /** Holds every answer until [release] — to overlap two refreshes. */
        @Volatile var held = false
        private val gate = CompletableDeferred<Unit>()

        override suspend fun send(call: HttpCall): Response {
            val uri = URI(call.url)
            val host = uri.host
            val login = uri.query?.split('&')?.firstOrNull { it.startsWith("login=") }?.removePrefix("login=") ?: ""
            synchronized(this) { asked += host }
            if (held) gate.await()
            val answer = synchronized(this) { answers["$host/$login"] ?: answers[host] } ?: (500 to "{}")
            val headers = if (answer.first == 429) mapOf("Retry-After" to "60") else emptyMap()
            return Response(answer.first, headers, answer.second.encodeToByteArray())
        }

        fun answer(host: String, login: String? = null, used: Int) = synchronized(this) {
            answers[if (login != null) "$host/$login" else host] = 200 to """{"used":$used}"""
        }

        fun fail(host: String, status: Int = 500) = synchronized(this) { answers[host] = status to "{}" }

        fun requests(host: String): Int = synchronized(this) { asked.count { it == host } }

        fun release() {
            held = false
            gate.complete(Unit)
        }
    }

    private val api = "api.acme.test"
    private val backup = "backup.acme.test"
    private val stubs = mutableListOf<StubbedProvider>()

    @AfterEach
    fun cleanUp() = stubs.forEach { it.cleanUp() }

    private fun acme(
        network: AcmeNetwork,
        settings: InMemoryProviderSettings = InMemoryProviderSettings(),
        definition: ProviderDefinition = acme(),
        logins: List<String> = emptyList(),
    ): Provider {
        val stub = StubbedProvider(network = network).also { stubs += it }
        return stub.make(
            definition,
            accounts = logins.map { ProviderAccountConfig(it, "", probeConfig = mapOf("login" to it)) },
            settings = settings,
        )
    }

    // Refresh

    @Test
    fun `should show a login's usage under its own id and say which data source answered`() {
        val network = AcmeNetwork()
        network.answer(api, used = 30)
        val acme = acme(network, logins = listOf("work"))
        val work = acme.accounts[1]

        val usage = acme.refreshNow(work).usage()

        assertEquals("acme.work", usage.providerId)
        assertEquals(70.0, work.snapshot?.sessionQuota?.percentRemaining)
        assertEquals("api", work.answeredBy)
        assertNull(work.lastError)
    }

    @Test
    fun `should keep the last usage and say which step failed when a refresh fails`() {
        val network = AcmeNetwork()
        network.answer(backup, used = 30)
        val acme = acme(network)
        acme.configuration.use("backup")
        acme.refreshPlain().usage()
        network.fail(backup)

        assertTrue(acme.refreshPlain() is RefreshOutcome.Failed)

        assertEquals(70.0, acme.defaultAccount.snapshot?.sessionQuota?.percentRemaining)
        assertNotNull(acme.defaultAccount.lastError)
        assertEquals(DataSourceError.Step.FETCH, acme.defaultAccount.lastFailedStep)
    }

    @Test
    fun `should leave another login's usage alone when one login fails`() {
        val network = AcmeNetwork()
        network.answer(api, login = "home", used = 10)
        network.fail(backup)
        val acme = acme(network, logins = listOf("home", "work"))

        acme.refreshNow(acme.accounts[1]).usage()
        assertTrue(acme.refreshNow(acme.accounts[2]) is RefreshOutcome.Failed)

        assertEquals(90.0, acme.accounts[1].snapshot?.sessionQuota?.percentRemaining)
        assertNull(acme.accounts[1].lastError)
        assertNull(acme.accounts[2].snapshot)
    }

    @Test
    fun `should run a background refresh's fetch at the utility priority, and a click's at the default (#204)`() {
        val priorities = Collections.synchronizedList(mutableListOf<QualityOfService>())
        val network = object : NetworkClient {
            override suspend fun send(call: HttpCall): Response {
                priorities += currentQualityOfService()
                return Response(200, emptyMap(), """{"used":30}""".encodeToByteArray())
            }
        }
        val stub = StubbedProvider(network = network).also { stubs += it }
        val acme = stub.make(acme(), settings = InMemoryProviderSettings())
        // The data source without a cache, so both refreshes ask.
        acme.configuration.use("backup")

        acme.refreshPlain(RefreshKind.BACKGROUND).usage()
        acme.refreshPlain(RefreshKind.INTERACTIVE).usage()

        assertEquals(listOf(QualityOfService.UTILITY, QualityOfService.DEFAULT), priorities.toList())
    }

    @Test
    fun `should ask the provider once when one login is refreshed twice at the same time`() = runBlocking {
        val network = AcmeNetwork()
        network.answer(api, used = 30)
        network.held = true
        val acme = acme(network)

        val first = async { acme.refresh(acme.defaultAccount) }
        val second = async { acme.refresh(acme.defaultAccount) }
        delay(50)
        network.release()
        val outcomes = awaitAll(first, second)

        assertTrue(outcomes.all { it is RefreshOutcome.Refreshed })
        assertEquals(1, network.requests(api))
    }

    // Fallback

    @Test
    fun `should show the fallback's usage, and say it answered, when the chosen data source fails`() {
        val network = AcmeNetwork()
        network.fail(api)
        network.answer(backup, used = 40)
        val acme = acme(network)

        val usage = acme.refreshPlain().usage()

        assertEquals(60.0, usage.sessionQuota?.percentRemaining)
        assertEquals("backup", acme.defaultAccount.answeredBy)
    }

    @Test
    fun `should report the chosen data source's failure when every data source fails`() {
        val network = AcmeNetwork()
        network.fail(api, status = 401)
        network.fail(backup, status = 500)
        val acme = acme(network)

        assertTrue(acme.refreshPlain() is RefreshOutcome.Failed)

        assertEquals("authenticationRequired", acme.defaultAccount.lastError?.tag)
    }

    @Test
    fun `should not ask the fallback when the person switched it off`() {
        val network = AcmeNetwork()
        network.fail(api)
        network.answer(backup, used = 40)
        val acme = acme(network)
        acme.configuration.setFallbackEnabled(false, "api")

        assertTrue(acme.refreshPlain() is RefreshOutcome.Failed)

        assertEquals(0, network.requests(backup))
    }

    @Test
    fun `should not ask the fallback when the chosen data source is rate-limited`() {
        val network = AcmeNetwork()
        network.fail(api, status = 429)
        network.answer(backup, used = 40)
        val acme = acme(network)

        assertTrue(acme.refreshPlain() is RefreshOutcome.Failed)

        assertEquals(0, network.requests(backup))
    }

    @Test
    fun `should use the next data source on the fallback chain when a login cannot use the chosen one`() {
        val network = AcmeNetwork()
        network.answer(backup, used = 25)
        val acme = acme(network, definition = acme(patch = loginPatch + ("api" to JsonNull)), logins = listOf("work"))

        val usage = acme.refreshNow(acme.accounts[1]).usage()

        assertEquals(75.0, usage.sessionQuota?.percentRemaining)
        assertEquals("backup", acme.accounts[1].answeredBy)
        assertEquals(0, network.requests(api))
    }

    // The data source choice — one for every login

    @Test
    fun `should save the chosen data source and refuse one the provider does not have`() {
        val settings = InMemoryProviderSettings()
        val acme = acme(AcmeNetwork(), settings = settings)

        assertTrue(acme.configuration.use("backup"))
        assertFalse(acme.configuration.use("tty"))

        assertEquals("backup", acme.configuration.activeKind)
        assertEquals("backup", settings.dataSourceKind("acme"))
    }

    @Test
    fun `should ask in the background no more often than the chosen data source's cache allows`() {
        val acme = acme(AcmeNetwork())

        assertEquals(600.0, acme.backgroundRefreshFloorSeconds)
        acme.configuration.use("backup")
        assertNull(acme.backgroundRefreshFloorSeconds)
    }

    // Held back until checked (#216)

    @Test
    fun `should not ask in the background until the person has refreshed once, when the data source must be checked first (#216)`() {
        val network = AcmeNetwork()
        network.answer(api, used = 30)
        val acme = acme(network, definition = acme(verifyBeforeBackground = true))

        assertTrue(acme.refreshPlain(RefreshKind.BACKGROUND) is RefreshOutcome.Failed)
        assertEquals(0, network.requests(api))

        acme.refreshPlain(RefreshKind.INTERACTIVE).usage()
        acme.refreshPlain(RefreshKind.BACKGROUND).usage()
        assertEquals(1, network.requests(api))
    }

    // Status across logins

    @Test
    fun `should take the worst enabled login's status, and call the login with the most left the best`() {
        val network = AcmeNetwork()
        network.answer(api, used = 40)
        network.answer(api, login = "low", used = 90)
        network.answer(api, login = "high", used = 10)
        val acme = acme(network, logins = listOf("low", "high"))
        for (account in acme.accounts) acme.refreshNow(account).usage()

        assertEquals(QuotaStatus.CRITICAL, acme.status)
        assertEquals("high", acme.accounts.best?.accountId)

        acme.accounts[1].isEnabled = false
        assertEquals(QuotaStatus.HEALTHY, acme.status)
    }

    @Test
    fun `should name the login that makes the provider's status, and none when all is well`() {
        val network = AcmeNetwork()
        network.answer(api, used = 40)
        network.answer(api, login = "low", used = 90)
        val acme = acme(network, logins = listOf("low"))

        assertNull(acme.accounts.worst)
        for (account in acme.accounts) acme.refreshNow(account).usage()

        assertEquals("low", acme.accounts.worst?.accountId)
        acme.accounts[1].isEnabled = false
        assertNull(acme.accounts.worst)
    }
}
