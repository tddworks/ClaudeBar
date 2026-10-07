package com.tddworks.claudebar.datasources

import com.tddworks.claudebar.datasources.lookup.FakeCookies
import com.tddworks.claudebar.datasources.lookup.FakeDatabase
import com.tddworks.claudebar.datasources.lookup.FakeSecurity
import com.tddworks.claudebar.datasources.lookup.FakeStorage
import com.tddworks.claudebar.datasources.lookup.SQLiteReading
import com.tddworks.claudebar.datasources.lookup.SecurityResult
import com.tddworks.claudebar.datasources.lookup.SecurityTool
import com.tddworks.claudebar.datasources.mapping.ScriptEngine
import com.tddworks.claudebar.datasources.mapping.ScriptRun
import com.tddworks.claudebar.datasources.process.CLIWorkingDirectory
import com.tddworks.claudebar.datasources.process.DiskFiles
import com.tddworks.claudebar.datasources.process.FakeCLIExecutor
import com.tddworks.claudebar.datasources.process.FakeFiles
import com.tddworks.claudebar.datasources.process.FakeMachine
import com.tddworks.claudebar.datasources.process.MachineFiles
import com.tddworks.claudebar.datasources.process.RPCTransportFactory
import kotlinx.serialization.json.Json
import java.io.File
import java.util.Collections

// The test harness for the factory: a `DataSources` built from fakes, the way the Swift suites
// called `DataSources.make(…, cliExecutor:, network:, makeTransport:, environment:, homeDirectory:, now:)`.

/** 2023-11-14 22:13:20 UTC — the Swift suites' fixed "now". */
internal const val TEST_NOW = 1_700_000_000.0

/** Where a `dedicated` CLI runs in these tests: ClaudeBar's own folder on a fake Mac. */
internal val DEDICATED_FOLDER: String = CLIWorkingDirectory.resolve(FakeMachine(), FakeFiles())

/** A data source definition as JSON. */
internal fun definition(json: String): DataSourceDefinition = DataSourceDefinition.from(Json.parseToJsonElement(json))

/** A JVM temporary folder, the Swift suites' `FileManager.default.temporaryDirectory`. */
internal val TEMP_HOME: String = System.getProperty("java.io.tmpdir").trimEnd('/')

/** A fresh, empty folder under the temporary folder. */
internal fun freshFolder(prefix: String): File =
    File(TEMP_HOME, "$prefix-${java.util.UUID.randomUUID()}").apply { mkdirs() }

/** Every port of the factory as a fake, each overridable. */
internal fun testDataSources(
    network: NetworkClient = AnsweringNetwork(),
    cli: CLIExecutor = FakeCLIExecutor(),
    transports: RPCTransportFactory = RPCTransportFactory { _, _, _, _ -> AnsweringTransport() },
    environment: Map<String, String> = emptyMap(),
    home: String = TEMP_HOME,
    now: () -> Double = { TEST_NOW },
    loginShell: ((String) -> String?)? = null,
    files: MachineFiles = DiskFiles,
    loopback: NetworkClient = network,
    security: SecurityTool = FakeSecurity { SecurityResult(44, "") },
    database: SQLiteReading = FakeDatabase { _, _ -> emptyList() },
    browserCookies: BrowserCookieReading = FakeCookies(),
    browserStorage: BrowserStorageReading = FakeStorage(),
    cloudWatch: CloudWatchClient? = null,
    priceCatalog: PriceCatalog? = null,
    scriptEngine: ScriptEngine = com.tddworks.claudebar.datasources.mapping.GraalScriptEngine(),
    processPaths: () -> List<String> = { emptyList() },
): DataSources = DataSources(
    home = home,
    environment = { environment[it] },
    network = network,
    loopback = loopback,
    makeCLIExecutor = { cli },
    makeCommandExecutor = { cli },
    transports = transports,
    directory = { DEDICATED_FOLDER },
    processEnvironment = { environment },
    files = files,
    processPaths = processPaths,
    security = security,
    database = database,
    browserCookies = browserCookies,
    browserStorage = browserStorage,
    loginShell = loginShell,
    cloudWatch = cloudWatch,
    priceCatalog = priceCatalog,
    scriptEngine = scriptEngine,
    now = now,
)

/** A network that answers every request with [answer] (an empty 200 by default), keeping each one sent. */
internal class AnsweringNetwork(private val answer: (HttpCall) -> Response = { Response(200, body = ByteArray(0)) }) : NetworkClient {
    val sent: MutableList<HttpCall> = Collections.synchronizedList(mutableListOf())

    override suspend fun send(call: HttpCall): Response {
        sent += call
        return answer(call)
    }

    companion object {
        /** Every request answered with [status], [body] and [headers]. */
        fun answering(body: String, status: Int = 200, headers: Map<String, String> = emptyMap()) =
            AnsweringNetwork { Response(status, headers, body.encodeToByteArray()) }
    }
}

/** A JSON-RPC pipe that answers every request with [answer]; it remembers being closed. */
internal class AnsweringTransport(private val answer: String = """{"id":1,"result":{}}""") : RPCTransport {
    val sent = mutableListOf<String>()
    var closed = false
        private set

    override fun send(data: ByteArray) {
        sent += data.decodeToString()
    }

    override suspend fun receive(): ByteArray = answer.encodeToByteArray()

    override fun close() {
        closed = true
    }
}

/** No JavaScript engine on the JVM: a script mapping says so. */
internal object NoScriptEngine : ScriptEngine {
    override fun run(
        sources: List<String>,
        strings: Map<String, String>,
        functions: Map<String, (String) -> Double?>,
        expression: String,
    ): ScriptRun = ScriptRun.Unavailable
}

/** What [block] threw, or null when it returned. */
internal suspend fun thrown(block: suspend () -> Unit): Throwable? = try {
    block()
    null
} catch (error: Throwable) {
    error
}
