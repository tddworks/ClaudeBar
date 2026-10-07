package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.BrowserCookie
import com.tddworks.claudebar.datasources.HttpCall
import com.tddworks.claudebar.datasources.NetworkClient
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.datasources.TEMP_HOME
import com.tddworks.claudebar.datasources.lookup.FakeCookies
import com.tddworks.claudebar.datasources.process.InMemoryLoginFolders
import com.tddworks.claudebar.datasources.testDataSources
import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageError
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.CsvSource
import java.net.URI
import java.net.URLDecoder
import java.util.Collections

/**
 * Alibaba on stubbed connections: an API key, or the console session — a pasted cookie or the
 * browser's — whose `sec_token` comes from the cookie or, failing that, from the console page.
 */
class AlibabaExecutionTest {
    private val quota = """{"data":{"codingPlanInstanceInfos":[{"status":"VALID","planName":"Pro","codingPlanQuotaInfo":{"per5HourUsedQuota":10,"per5HourTotalQuota":100,"perWeekUsedQuota":25,"perWeekTotalQuota":500,"perBillMonthUsedQuota":50,"perBillMonthTotalQuota":2000,"perBillMonthQuotaNextRefreshTime":"2026-03-01T00:00:00Z"}}]}}"""

    private class Sent {
        val requests: MutableList<HttpCall> = Collections.synchronizedList(mutableListOf())
        fun last(host: String): HttpCall? = requests.lastOrNull { URI(it.url).host == host }
    }

    private val HttpCall.path: String get() = URI(url).path
    private val HttpCall.query: String? get() = URI(url).rawQuery
    private val HttpCall.text: String get() = body?.decodeToString() ?: ""
    private fun HttpCall.header(name: String): String? = headers.entries.firstOrNull { it.key.equals(name, ignoreCase = true) }?.value

    /** Alibaba with its old card's settings where it kept them. */
    private fun make(
        region: String? = null, mode: String? = null, status: Int = 200, vault: MemoryVault = MemoryVault(),
        browser: List<BrowserCookie> = emptyList(), page: String = "", sent: Sent = Sent(), quota: String = this.quota,
    ): Provider {
        val network = object : NetworkClient {
            override suspend fun send(call: HttpCall): Response {
                sent.requests += call
                if (call.method == "GET") return Response(200, body = page.encodeToByteArray())
                return Response(status, body = quota.encodeToByteArray())
            }
        }
        val settings = InMemoryProviderSettings()
        settings.setValue(region, "region", "alibaba")
        if (mode != null) settings.setDataSourceKind(mode, "alibaba")
        val definition = TestDefinitions.builtIn("alibaba")
        val connections = testDataSources(
            network = network,
            browserCookies = FakeCookies(if (browser.isEmpty()) emptyList() else listOf(browser)),
            environment = emptyMap(),
        )
        return Provider(
            definition = definition, settings = settings, saved = settings.accounts("alibaba"),
            makeDataSource = { source, login -> connections.make(source, definition.id, vault.scoped(login), TestDefinitions.builtIns::script) },
            folders = InMemoryLoginFolders(), vault = vault, paths = HomePaths(TEMP_HOME),
            isExecutable = { true }, locate = { it },
        )
    }

    private fun RefreshOutcome.failure(): UsageError {
        assertTrue(this is RefreshOutcome.Failed, "expected a failure, got $this")
        return (this as RefreshOutcome.Failed).error
    }

    @Test
    fun `should keep Alibaba's name and dashboard, off until the person turns it on`() {
        val provider = make()
        assertEquals("Alibaba", provider.name)
        assertFalse(provider.plainIsInLineup)
        assertEquals("https://modelstudio.console.alibabacloud.com/ap-southeast-1/?tab=coding-plan#/efm/detail", provider.plainDashboardURL)
    }

    // API key

    @Test
    fun `should show the plan from the region's gateway when the person has an API key`() {
        val sent = Sent()
        val snapshot = make(vault = MemoryVault(mapOf("alibaba.apiKey" to "sk-1")), sent = sent).refreshPlain().usage()
        assertEquals(listOf(QuotaType.Session, QuotaType.Weekly, QuotaType.TimeLimit("Monthly")), snapshot.quotas.map { it.quotaType })
        assertEquals("Pro", snapshot.loginMethod)
        val request = sent.last("modelstudio.console.alibabacloud.com")!!
        assertEquals("/data/api.json", request.path)
        assertTrue(request.query?.contains("currentRegionId=ap-southeast-1") == true)
        assertEquals("Bearer sk-1", request.header("Authorization"))
        assertEquals("sk-1", request.header("X-DashScope-API-Key"))
        assertTrue(request.text.contains("sfm_codingplan_public_intl"))
    }

    @Test
    fun `should ask China Mainland's own gateway, commodity and dashboard when that region is chosen`() {
        val sent = Sent()
        val provider = make(region = "cn", vault = MemoryVault(mapOf("alibaba.apiKey" to "sk-1")), sent = sent)
        provider.refreshPlain()
        val request = sent.last("bailian.console.aliyun.com")
        assertNotNull(request)
        assertTrue(request!!.query?.contains("currentRegionId=cn-beijing") == true)
        assertTrue(request.text.contains("sfm_codingplan_public_cn"))
        assertEquals("bailian.console.aliyun.com", provider.plainDashboardURL?.let { URI(it).host })
    }

    @Test
    fun `should give the billing month the length of the month ending on its reset`() {
        val snapshot = make(vault = MemoryVault(mapOf("alibaba.apiKey" to "sk-1"))).refreshPlain().usage()
        val month = snapshot.quota(QuotaType.TimeLimit("Monthly"))
        assertNotNull(month)
        assertEquals((28 * 86400).toDouble(), month!!.window?.lengthSeconds)
    }

    @ParameterizedTest
    @CsvSource("2024-03-01T00:00:00Z, 29", "2026-03-31T00:00:00Z, 31", "2026-01-31T00:00:00Z, 31")
    fun `should measure billing months in UTC and clamp the previous month end`(reset: String, days: Int) {
        val quota = quota.replace("2026-03-01T00:00:00Z", reset)
        val snapshot = make(vault = MemoryVault(mapOf("alibaba.apiKey" to "fake")), quota = quota).refreshPlain().usage()
        assertEquals((days * 86400).toDouble(), snapshot.quota(QuotaType.TimeLimit("Monthly"))?.window?.lengthSeconds)
    }

    // Console cookie

    @Test
    fun `should use the browser's console session when there is no API key`() {
        val sent = Sent()
        val browser = listOf(
            BrowserCookie("login_aliyunid_ticket", "t"), BrowserCookie("login_aliyunid_csrf", "c-1"),
            BrowserCookie("sec_token", "s-1"),
        )
        val snapshot = make(browser = browser, sent = sent).refreshPlain().usage()
        assertEquals(3, snapshot.quotas.size)
        // The cookie held sec_token: the console page isn't asked.
        assertTrue(sent.requests.all { it.method == "POST" })
        val request = sent.last("bailian-singapore-cs.alibabacloud.com")!!
        assertTrue(request.query?.contains("action=IntlBroadScopeAspnGateway") == true)
        assertEquals("login_aliyunid_ticket=t; login_aliyunid_csrf=c-1; sec_token=s-1", request.header("Cookie"))
        assertEquals("c-1", request.header("x-csrf-token"))
        val body = request.text
        assertTrue(body.endsWith("&region=ap-southeast-1&sec_token=s-1"), body)
        assertTrue(URLDecoder.decode(body.replace("+", "%2B"), "UTF-8").contains(""""commodityCode":"sfm_codingplan_public_intl""""))
    }

    @Test
    fun `should take the console token from the console page when the pasted cookie has none`() {
        val sent = Sent()
        val provider = make(
            mode = "cookie", vault = MemoryVault(mapOf("alibaba.cookie" to "login_aliyunid_ticket=t")),
            page = """<script>window.ALIYUN = {"sec_token": "page-9"}</script>""", sent = sent,
        )
        provider.refreshPlain()
        val page = sent.requests.first { it.method == "GET" }
        assertEquals("login_aliyunid_ticket=t", page.header("Cookie"))
        val request = sent.last("bailian-singapore-cs.alibabacloud.com")!!
        assertTrue(request.text.endsWith("&sec_token=page-9"))
        // No CSRF cookie: no x-csrf-token header rather than a failure.
        assertNull(request.header("x-csrf-token"))
    }

    @Test
    fun `should send the pasted cookie before the browser's`() {
        val sent = Sent()
        make(
            mode = "cookie", vault = MemoryVault(mapOf("alibaba.cookie" to "sec_token=pasted")),
            browser = listOf(BrowserCookie("sec_token", "browser")), sent = sent,
        ).refreshPlain()
        assertEquals("sec_token=pasted", sent.last("bailian-singapore-cs.alibabacloud.com")?.header("Cookie"))
    }

    @Test
    fun `should ask to sign in again when the console session is refused`() {
        val error = make(mode = "cookie", status = 401, vault = MemoryVault(mapOf("alibaba.cookie" to "sec_token=s"))).refreshPlain().failure()
        assertTrue(error is UsageError.SessionExpired, "$error")
        assertEquals("Re-authenticate in Alibaba Cloud console.", (error as UsageError.SessionExpired).hint)
    }

    @Test
    fun `should not be available when there is no key and no cookie anywhere`() {
        assertFalse(make().isPlainAvailable())
    }

    // Accounts

    @Test
    fun `should ask an added account for what the chosen data source uses`() {
        assertEquals(listOf("apiKey", "region"), make().accounts.form.map { it.id })
        assertEquals(listOf("cookie", "region"), make(mode = "cookie").accounts.form.map { it.id })
    }

    @Test
    fun `should use an added cookie account's own cookie, never the browser's`() {
        val sent = Sent()
        val provider = make(mode = "cookie", browser = listOf(BrowserCookie("sec_token", "browser")), sent = sent)
        val work = provider.accounts.add(mapOf("cookie" to "sec_token=work", "region" to "cn")).done()
        provider.refreshNow(work)
        val request = sent.last("bailian-beijing-cs.aliyuncs.com")
        assertNotNull(request)
        assertEquals("sec_token=work", request!!.header("Cookie"))
    }
}
