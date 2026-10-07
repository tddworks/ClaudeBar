package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.BrowserCookie
import com.tddworks.claudebar.datasources.BrowserCookieReading
import com.tddworks.claudebar.datasources.BrowserStorageReading
import com.tddworks.claudebar.datasources.CLIExecutor
import com.tddworks.claudebar.datasources.CLIResult
import com.tddworks.claudebar.datasources.DataSources
import com.tddworks.claudebar.datasources.HttpCall
import com.tddworks.claudebar.datasources.NetworkClient
import com.tddworks.claudebar.datasources.RPCTransport
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.datasources.SecretVault
import com.tddworks.claudebar.datasources.lookup.SQLiteReading
import com.tddworks.claudebar.datasources.lookup.SecurityResult
import com.tddworks.claudebar.datasources.lookup.SecurityTool
import com.tddworks.claudebar.datasources.lookup.StoredValue
import com.tddworks.claudebar.datasources.mapping.NoScriptEngine
import com.tddworks.claudebar.datasources.mapping.ScriptEngine
import com.tddworks.claudebar.datasources.process.AccountSignIn
import com.tddworks.claudebar.datasources.process.DiskFiles
import com.tddworks.claudebar.datasources.process.InMemoryLoginFolders
import com.tddworks.claudebar.datasources.process.RPCTransportFactory
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.intOrNull
import java.io.File
import java.nio.file.Files
import java.time.Instant
import java.util.Base64
import java.util.Collections
import java.util.concurrent.TimeUnit

/**
 * Builds a `Provider` — a bundled definition, or any other — whose data sources run on stubbed
 * connections, so a definition is tested end to end (lookup, fetch, mapping, lifecycle)
 * without a network, a CLI or the person's home directory. The per-vendor suites build on it:
 * `StubbedProvider("codex")`, answer what the connection should say, `makeProvider("codex")`,
 * refresh.
 *
 * The home is a real temporary folder, written one way (symlinks resolved), so file lookups,
 * signed-in folders and usage logs read real files.
 */
internal class StubbedProvider(
    providerId: String? = null,
    dataSourceKind: String? = null,
    /** The network; [answerHTTP] tells the default one what to say. */
    network: NetworkClient? = null,
) {
    val home: String = Files.createTempDirectory("providers-tests").toRealPath().toString()
    val settings = InMemoryProviderSettings(dataSourceKinds = if (providerId != null && dataSourceKind != null) mapOf(providerId to dataSourceKind) else emptyMap())
    val http = StubNetwork()
    private val network: NetworkClient = network ?: http

    /** The terminal CLIs: found or not, and what each run prints. */
    val cli = StubCLI()

    /** Commands and scripts run over pipes — a real `/bin/sh` unless told otherwise. */
    var commands: CLIExecutor = ShellCommands

    /** The JSON-RPC CLI, answering each request by its method. */
    val transport = StubRPCTransport()

    /** Every CLI started for JSON-RPC: its arguments and environment. */
    val launches: MutableList<Pair<List<String>, Map<String, String>?>> = Collections.synchronizedList(mutableListOf())

    /** The login folders adding and removing accounts makes and deletes. */
    val folders = InMemoryLoginFolders()

    /** Which login new terminal sessions start with — *In use*. */
    val loginsInUse = InMemoryLoginsInUse()

    var environment: Map<String, String> = emptyMap()

    /** What `/usr/bin/security` answers — by default, no such Keychain item. */
    var security: (List<String>) -> SecurityResult = { SecurityResult(44, "") }

    /** JavaScript mappings need an engine; the JVM has none, so a definition that maps with a script is read on the Mac. */
    var scriptEngine: ScriptEngine = NoScriptEngine

    var now: () -> Double = { System.currentTimeMillis() / 1000.0 }

    val builtIns = TestDefinitions.builtIns

    init {
        if (providerId == "codex") {
            // A signed-in CLI: Codex refuses to start without a login (#216).
            File(home, ".codex").mkdirs()
            File(home, ".codex/auth.json").writeText("{}")
        }
    }

    /** The data sources' connections, as the engine would hold them. */
    fun connections(): DataSources = DataSources(
        home = home,
        environment = { environment[it] },
        network = network,
        loopback = network,
        makeCLIExecutor = { cli },
        makeCommandExecutor = { change -> commands.let { if (it === ShellCommands) ShellCommands.with(change.set, change.unset) else it } },
        transports = RPCTransportFactory { executable, arguments, environment, _ ->
            launches += (listOf(executable) + arguments) to environment
            transport
        },
        directory = { "$home/Probe" },
        processEnvironment = { environment },
        files = DiskFiles,
        processPaths = { emptyList() },
        security = SecurityTool { security(it) },
        database = NoDatabase,
        browserCookies = NoBrowserCookies,
        browserStorage = NoBrowserStorage,
        loginShell = null,
        cloudWatch = null,
        priceCatalog = null,
        scriptEngine = scriptEngine,
        now = { now() },
    )

    /** The provider of a bundled definition, with its default login and every login in [accounts]. */
    fun makeProvider(
        id: String,
        accounts: List<ProviderAccountConfig> = emptyList(),
        isExecutable: (String) -> Boolean = { true },
        locate: (String) -> String? = { it },
        vault: SecretVault? = null,
        usageHistory: UsageHistory? = null,
        loginsInUse: LoginsInUse? = this.loginsInUse,
    ): Provider = make(builtIns.definition(id), accounts, isExecutable, locate, vault, usageHistory = usageHistory, loginsInUse = loginsInUse)

    /** The provider of any definition over these connections. */
    fun make(
        definition: ProviderDefinition,
        accounts: List<ProviderAccountConfig> = emptyList(),
        isExecutable: (String) -> Boolean = { true },
        locate: (String) -> String? = { it },
        vault: SecretVault? = null,
        paths: PathChecking = HomePaths(home) { environment[it] },
        settings: MultiAccountSettingsRepository = this.settings,
        usageHistory: UsageHistory? = null,
        guestPasses: GuestPasses? = null,
        loginsInUse: LoginsInUse? = this.loginsInUse,
    ): Provider {
        val connections = connections()
        return Provider(
            definition = definition,
            settings = settings,
            saved = accounts,
            makeDataSource = { source, login -> connections.make(source, definition.id, vault?.scoped(login), builtIns::script) },
            guestPasses = guestPasses,
            usageHistory = usageHistory,
            folders = folders,
            loginsInUse = loginsInUse,
            vault = vault,
            paths = paths,
            isExecutable = isExecutable,
            locate = locate,
            signInRoot = "$home/.claudebar/accounts",
            now = { now() },
            scope = CoroutineScope(SupervisorJob() + Dispatchers.Default),
        )
    }

    /** The provider with one saved login added, and that login — ask the provider about it. */
    fun makeAdded(id: String, account: ProviderAccountConfig): Pair<Provider, Account> {
        val provider = makeProvider(id, listOf(account))
        return provider to provider.accounts.first { it.accountId == account.accountId }
    }

    /** A sign-in whose CLI, wherever it is, does [run] in the folder it is given. */
    fun signIn(process: ScriptedSignIn): AccountSignIn = AccountSignIn(process, folders, { it }) { environment }

    fun cleanUp() {
        File(home).deleteRecursively()
    }

    // Stubbing helpers

    /** Every HTTP request answered with [body]. */
    fun answerHTTP(body: String, status: Int = 200, headers: Map<String, String> = emptyMap()) {
        http.answer = { Response(status, headers, body.encodeToByteArray()) }
    }

    /**
     * Each JSON-RPC request answered with its own id: `initialize` with nothing, `account/read`
     * with [account], anything else with [answer] — however many times the CLI is started.
     */
    fun answerRPC(answer: String, account: String = """{"id":3,"result":{"account":null}}""") {
        transport.reply = { method ->
            when (method) {
                "initialize" -> """{"id":1,"result":{}}"""
                "account/read" -> account
                else -> answer
            }
        }
    }

    /** The terminal CLI found, printing [screen]. */
    fun answerTerminal(screen: String) {
        cli.located = { "/usr/local/bin/$it" }
        cli.answer = { CLIResult(screen) }
    }

    /** Writes `~/.codex/auth.json` in the stubbed home. */
    fun writeCodexAuth(token: String = "test-access-token", accountId: String? = null, lastRefresh: Instant = Instant.now()) {
        val tokens = buildString {
            append("""{"access_token":"$token","refresh_token":"test-refresh-token"""")
            if (accountId != null) append(""","account_id":"$accountId"""")
            append("}")
        }
        File(home, ".codex").mkdirs()
        File(home, ".codex/auth.json").writeText("""{"tokens":$tokens,"last_refresh":"$lastRefresh"}""")
    }

    /** A Codex folder signed in as [email] with account [accountId], as its CLI writes it. */
    fun writeCodexLogin(folder: File, email: String?, accountId: String) {
        folder.mkdirs()
        val idToken = email?.let { ""","id_token":"${jwt("""{"email":"$it"}""")}"""" } ?: ""
        File(folder, "auth.json").writeText("""{"tokens":{"access_token":"t","account_id":"$accountId"$idToken}}""")
    }

    companion object {
        /** A JWT whose claims are [claims] — the signature is never checked. */
        fun jwt(claims: String): String = "h." + Base64.getUrlEncoder().withoutPadding().encodeToString(claims.toByteArray()) + ".s"
    }
}

/** Answers every request with [answer], keeping each one sent. */
internal class StubNetwork(var answer: (HttpCall) -> Response = { Response(status = 500, body = "{}".encodeToByteArray()) }) : NetworkClient {
    val sent: MutableList<HttpCall> = Collections.synchronizedList(mutableListOf())

    override suspend fun send(call: HttpCall): Response {
        sent += call
        return answer(call)
    }
}

/** A terminal CLI found where [located] says, printing what [answer] says (or throwing what it throws). */
internal class StubCLI(
    var located: (String) -> String? = { null },
    var answer: (List<String>) -> CLIResult = { throw UsageError.CliNotFound(it.first()) },
) : CLIExecutor {
    val runs: MutableList<List<String>> = Collections.synchronizedList(mutableListOf())

    override fun locate(binary: String): String? = located(binary)

    override suspend fun execute(
        binary: String, args: List<String>, input: String?, timeoutSeconds: Double,
        workingDirectory: String?, autoResponses: Map<String, String>,
    ): CLIResult {
        val run = listOf(binary) + args
        runs += run
        return answer(run)
    }
}

/** A JSON-RPC CLI: each request answered by [reply] for its method, carrying the request's own id. */
internal class StubRPCTransport(var reply: (method: String) -> String = { """{"result":{}}""" }) : RPCTransport {
    private var last: Pair<Int, String> = 0 to ""

    override fun send(data: ByteArray) {
        val message = runCatching { Json.parseToJsonElement(data.decodeToString()) as JsonObject }.getOrNull() ?: return
        val id = (message["id"] as? JsonPrimitive)?.intOrNull ?: return
        val method = (message["method"] as? JsonPrimitive)?.content ?: return
        synchronized(this) { last = id to method }
    }

    override suspend fun receive(): ByteArray {
        val (id, method) = synchronized(this) { last }
        val message = Json.parseToJsonElement(reply(method)) as JsonObject
        return JsonObject(message + ("id" to JsonPrimitive(id))).toString().encodeToByteArray()
    }

    override fun close() {}
}

/** Commands run by this Mac's `/bin/sh` over pipes, with the variables a call sets and unsets. */
internal object ShellCommands : CLIExecutor {
    override fun locate(binary: String): String? = with(emptyMap(), emptyList()).locate(binary)

    override suspend fun execute(
        binary: String, args: List<String>, input: String?, timeoutSeconds: Double,
        workingDirectory: String?, autoResponses: Map<String, String>,
    ): CLIResult = with(emptyMap(), emptyList()).execute(binary, args, input, timeoutSeconds, workingDirectory, autoResponses)

    fun with(set: Map<String, String>, unset: List<String>): CLIExecutor = Changed(set, unset)

    class Changed(private val set: Map<String, String>, private val unset: List<String>) : CLIExecutor {
        override fun locate(binary: String): String? = binary.takeIf { File(it).canExecute() }

        override suspend fun execute(
            binary: String, args: List<String>, input: String?, timeoutSeconds: Double,
            workingDirectory: String?, autoResponses: Map<String, String>,
        ): CLIResult {
            val builder = ProcessBuilder(listOf(binary) + args).redirectErrorStream(false)
            workingDirectory?.let { builder.directory(File(it)) }
            builder.environment().apply { unset.forEach(::remove); putAll(set) }
            val process = builder.start()
            input?.let { process.outputStream.use { stream -> stream.write(it.toByteArray()) } }
            val output = process.inputStream.bufferedReader().readText()
            if (!process.waitFor(timeoutSeconds.toLong().coerceAtLeast(1), TimeUnit.SECONDS)) {
                process.destroyForcibly()
                throw UsageError.Timeout
            }
            return CLIResult(output, process.exitValue())
        }
    }
}

private object NoDatabase : SQLiteReading {
    override fun rows(path: String, query: String, name: String, limit: Int): List<Map<String, StoredValue>> =
        throw UsageError.ExecutionFailed("No database in this test")
}

private object NoBrowserCookies : BrowserCookieReading {
    override fun stores(domains: List<String>, names: List<String>): List<List<BrowserCookie>> = emptyList()
}

private object NoBrowserStorage : BrowserStorageReading {
    override fun stores(origin: String): List<Map<String, String>> = emptyList()
}
