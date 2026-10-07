package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.DataSource
import com.tddworks.claudebar.datasources.DataSourceError
import com.tddworks.claudebar.datasources.HttpCall
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.datasources.lookup.SecurityResult
import com.tddworks.claudebar.datasources.process.TerminalRenderer
import com.tddworks.claudebar.quotas.UsageError
import com.tddworks.claudebar.quotas.UsageSnapshot
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.io.File
import java.math.BigDecimal

/**
 * Runs `claude.json`'s real data sources — and the JavaScript its mappings name — over stubbed
 * connections and a temporary home directory, as the Swift suites' `ClaudeHarness` does. Built on
 * [StubbedProvider]: its network, terminal CLI, Keychain and clock are this harness's.
 */
internal class ClaudeHarness {
    val stub = StubbedProvider("claude")
    val home: String get() = stub.home

    /** The network every data source and refresh asks; tell it what to say with [answer]. */
    val network: StubNetwork get() = stub.http

    /** The terminal CLI: found or not, and what each run prints. */
    val cli: StubCLI get() = stub.cli

    var environment: Map<String, String>
        get() = stub.environment
        set(value) { stub.environment = value }

    /** What `security find-generic-password … -w` answers, if anything. */
    var keychainPassword: String? = null

    var now: Double = System.currentTimeMillis() / 1000.0

    /** The folder CLI fetches run in — what `{{cliDirectory}}` names. */
    val cliDirectory: String get() = "$home/Probe"

    init {
        stub.now = { now }
        stub.security = { arguments ->
            val password = keychainPassword
            if (arguments.firstOrNull() == "find-generic-password" && password != null) SecurityResult(0, password) else SecurityResult(44, "")
        }
    }

    fun cleanUp() = stub.cleanUp()

    // Data sources

    /** One of `claude.json`'s data sources: `cli`, `cliCost` or `api`. */
    fun dataSource(kind: String): DataSource {
        val definition = stub.builtIns.definition("claude")
        return stub.connections().make(definition.dataSource(kind)!!, "claude", null, stub.builtIns::script)
    }

    /** A `Provider` built from `claude.json` over these connections. */
    fun provider(
        settings: MultiAccountSettingsRepository = InMemoryProviderSettings(),
        accounts: List<ProviderAccountConfig> = emptyList(),
        guestPasses: GuestPasses? = null,
    ): Provider = stub.make(stub.builtIns.definition("claude"), accounts, settings = settings, guestPasses = guestPasses)

    /** Every request answered by [reply]. */
    fun answer(reply: (HttpCall) -> Response) {
        network.answer = reply
    }

    // Reading screens and responses

    /** The `/usage` screen through `claude-usage-screen.js`; throws the `UsageError` the screen means. */
    fun readUsageScreen(screen: String): UsageSnapshot = unwrapped { dataSource("cli").read(Response(screen)) }

    /** Raw terminal bytes, drawn by the terminal emulator first — what the `cli` fetch does with `"screen": "rendered"`. */
    fun readRawUsageScreen(raw: String): UsageSnapshot = readUsageScreen(TerminalRenderer(160, 50).render(raw))

    /** The `/cost` screen through `claude-cost-screen.js`. */
    fun readCostScreen(screen: String): UsageSnapshot = unwrapped { dataSource("cliCost").read(Response(screen)) }

    /** A usage API body through claude.json's JSON mapping, with the plan the credential would carry. */
    fun readAPIResponse(json: String, subscriptionType: String? = null): UsageSnapshot {
        writeCredentials(subscriptionType = subscriptionType)
        answer { claudeResponse(200, body = json) }
        return fetchUsage(dataSource("api"))
    }

    /** `fetchUsage()`, throwing the `UsageError` inside a `DataSourceError`. */
    fun fetchUsage(source: DataSource): UsageSnapshot = unwrapped { runBlocking { source.fetchUsage() } }

    /** The `UsageError` a fetch threw, or null when it succeeded. */
    fun failure(source: DataSource): UsageError? = try {
        fetchUsage(source)
        null
    } catch (error: UsageError) {
        error
    }

    private fun <T> unwrapped(read: () -> T): T = try {
        read()
    } catch (failure: DataSourceError) {
        throw failure.reason
    }

    // Files

    /** `~/.claude.json` with the account fields the CLI data source reads. */
    fun writeClaudeConfig(
        email: String? = null,
        displayName: String? = null,
        billingType: String? = null,
        extra: Map<String, JsonElement> = emptyMap(),
    ) {
        val account = buildMap {
            email?.let { put("emailAddress", JsonPrimitive(it)) }
            displayName?.let { put("displayName", JsonPrimitive(it)) }
            billingType?.let { put("billingType", JsonPrimitive(it)) }
        }
        val config = extra.toMutableMap()
        if (account.isNotEmpty()) config["oauthAccount"] = JsonObject(account)
        File(home, ".claude.json").writeText(JsonObject(config).toString())
    }

    fun readClaudeConfig(): JsonObject = Json.parseToJsonElement(File(home, ".claude.json").readText()) as JsonObject

    /** `~/.claude/.credentials.json`. */
    fun writeCredentials(
        accessToken: String = "test-access-token",
        refreshToken: String? = "test-refresh-token",
        expiresAt: Double? = (System.currentTimeMillis() / 1000.0 + 3600) * 1000,
        subscriptionType: String? = null,
        extra: Map<String, JsonElement> = emptyMap(),
    ) {
        val oauth = extra.toMutableMap()
        oauth["accessToken"] = JsonPrimitive(accessToken)
        refreshToken?.let { oauth["refreshToken"] = JsonPrimitive(it) }
        expiresAt?.let { oauth["expiresAt"] = claudeNumber(it) }
        subscriptionType?.let { oauth["subscriptionType"] = JsonPrimitive(it) }
        writeClaudeCredentials(File(home, ".claude"), JsonObject(oauth))
    }

    fun readCredentials(): JsonObject {
        val document = Json.parseToJsonElement(File(home, ".claude/.credentials.json").readText()) as? JsonObject
        return document?.get("claudeAiOauth") as? JsonObject ?: JsonObject(emptyMap())
    }

    /** A separate Claude config folder (`CLAUDE_CONFIG_DIR`) signed in as [email]: its `.claude.json` and `.credentials.json`. */
    fun writeLogin(name: String, email: String?, token: String = "token"): File {
        val folder = File(home, name).apply { mkdirs() }
        val config = email?.let { mapOf("oauthAccount" to JsonObject(mapOf("emailAddress" to JsonPrimitive(it)))) } ?: emptyMap()
        File(folder, ".claude.json").writeText(JsonObject(config).toString())
        writeClaudeCredentials(folder, JsonObject(mapOf(
            "accessToken" to JsonPrimitive(token),
            "subscriptionType" to JsonPrimitive("pro"),
            "expiresAt" to claudeNumber((System.currentTimeMillis() / 1000.0 + 3600) * 1000),
        )))
        return folder
    }
}

/** A Claude config folder's `.credentials.json` holding [oauth]. */
internal fun writeClaudeCredentials(folder: File, oauth: JsonObject) {
    folder.mkdirs()
    File(folder, ".credentials.json").writeText(JsonObject(mapOf("claudeAiOauth" to oauth)).toString())
}

/** A number as `JSONSerialization` writes it: plain digits, never an exponent. */
internal fun claudeNumber(value: Double): JsonPrimitive = JsonPrimitive(BigDecimal.valueOf(value))

/** An answer from Claude's API. */
internal fun claudeResponse(status: Int, headers: Map<String, String> = emptyMap(), body: String = ""): Response =
    Response(status, headers, body.encodeToByteArray())

/** Whether [call] renews the login rather than asks for usage. */
internal val HttpCall.isClaudeTokenRequest: Boolean get() = url.contains("oauth/token")

/** The `Authorization` header a request carried. */
internal val HttpCall.claudeAuthorization: String?
    get() = headers.entries.firstOrNull { it.key.equals("Authorization", ignoreCase = true) }?.value
