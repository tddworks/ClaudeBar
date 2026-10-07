package com.tddworks.claudebar.datasources

import com.tddworks.claudebar.datasources.fetch.CloudWatchFetcher
import com.tddworks.claudebar.datasources.fetch.DirectoryFetcher
import com.tddworks.claudebar.datasources.fetch.FileFetcher
import com.tddworks.claudebar.datasources.fetch.HTTPFetcher
import com.tddworks.claudebar.datasources.fetch.HTTPStepsFetcher
import com.tddworks.claudebar.datasources.lookup.CredentialFinders
import com.tddworks.claudebar.datasources.lookup.SQLiteReading
import com.tddworks.claudebar.datasources.lookup.SecurityTool
import com.tddworks.claudebar.datasources.mapping.ScriptEngine
import com.tddworks.claudebar.datasources.mapping.reader
import com.tddworks.claudebar.datasources.process.CLIExecutorFactory
import com.tddworks.claudebar.datasources.process.CLIFetcher
import com.tddworks.claudebar.datasources.process.CommandExecutorFactory
import com.tddworks.claudebar.datasources.process.CommandFetcher
import com.tddworks.claudebar.datasources.process.JSONRPCFetcher
import com.tddworks.claudebar.datasources.process.LocalServerFetcher
import com.tddworks.claudebar.datasources.process.MachineFiles
import com.tddworks.claudebar.datasources.process.RPCTransportFactory
import com.tddworks.claudebar.datasources.process.ScriptFetcher
import com.tddworks.claudebar.diagnostics.AppLog
import kotlinx.io.buffered
import kotlinx.io.files.Path
import kotlinx.io.files.SystemFileSystem
import kotlinx.io.readString
import kotlinx.io.writeString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

/**
 * The context's factory: the only place a case of `Fetch`, `Mapping` or `CredentialLookup` meets
 * the one connection it needs. Built once by the composition root with everything that touches
 * this Mac (`DataSources.system` on macOS); tests hand in fakes. Callers get a `DataSource` and
 * never name a worker.
 */
internal class DataSources(
    private val home: String,
    private val environment: (String) -> String?,
    private val network: NetworkClient,
    /** Self-signed TLS accepted on 127.0.0.1 only — a local server's own. */
    private val loopback: NetworkClient,
    private val makeCLIExecutor: CLIExecutorFactory,
    private val makeCommandExecutor: CommandExecutorFactory,
    private val transports: RPCTransportFactory,
    /** Where a call's `workingDirectory` is on this Mac. */
    private val directory: (WorkingDirectory) -> String,
    /** The app's own environment, which a JSON-RPC CLI starts from. */
    private val processEnvironment: () -> Map<String, String>,
    private val files: MachineFiles,
    /** The executable paths running now. */
    private val processPaths: () -> List<String>,
    private val security: SecurityTool,
    private val database: SQLiteReading,
    private val browserCookies: BrowserCookieReading,
    private val browserStorage: BrowserStorageReading,
    private val loginShell: ((String) -> String?)?,
    private val cloudWatch: CloudWatchClient?,
    private val priceCatalog: PriceCatalog?,
    private val scriptEngine: ScriptEngine,
    private val now: () -> Double,
) {
    /** A definition's path as the app sees it: `~` and `${VARIABLE:-default}` filled in. */
    fun expandPath(path: String): String = Paths.expand(path, home, environment)

    /**
     * A live data source for one definition. [secrets] is the login's vault (a `setting` lookup,
     * a script's keys); [scripts] gives a mapping script's text by the file name a definition uses.
     */
    fun make(
        definition: DataSourceDefinition,
        providerId: String,
        secrets: SecretStore? = null,
        scripts: (String) -> String? = { null },
    ): DataSource {
        val finders = CredentialFinders(
            providerId, home, environment, security, secrets, database, browserCookies, browserStorage, loginShell,
        )
        val fetcher: Fetching = when (val fetch = definition.fetch) {
            is Fetch.Http -> HTTPFetcher(fetch.request, network, now)
            is Fetch.HttpSteps -> HTTPStepsFetcher(fetch.steps, network, now)
            is Fetch.JsonRpc ->
                JSONRPCFetcher(fetch.call, makeCLIExecutor(CLICall(cli = fetch.call.cli)), transports, directory, processEnvironment)
            is Fetch.Cli -> CLIFetcher(fetch.call, makeCLIExecutor, directory)
            is Fetch.Command -> CommandFetcher(fetch.call, makeCommandExecutor, directory)
            is Fetch.File -> FileFetcher(fetch.call, home, environment)
            is Fetch.LocalServer ->
                LocalServerFetcher(fetch.call, makeCommandExecutor(ProcessEnvironment()), loopback, processPaths)
            is Fetch.CloudWatch -> CloudWatchFetcher(fetch.call, cloudWatch, priceCatalog, now)
            is Fetch.Directory -> DirectoryFetcher(fetch.call, home, environment)
            is Fetch.Sqlite -> finders.sqliteFetcher(fetch.call)
            is Fetch.Script -> ScriptFetcher(fetch.call, providerId, secrets, makeCommandExecutor, files)
        }
        val (lookup, refresh) = definition.credential?.let(CredentialFinders::split) ?: (null to null)
        val refresher = refresh?.let {
            CredentialFinders.refresher(it, network, makeCLIExecutor, now, directory(WorkingDirectory.DEDICATED))
        }
        return DataSource(
            definition = definition,
            providerId = providerId,
            credentials = lookup?.let(finders::reader),
            refresher = refresher,
            fetcher = fetcher,
            mapper = definition.mapping.reader(scripts, scriptEngine, now),
            contextFiles = definition.context.mapValues { finders.contextFile(it.value) },
            recoveries = definition.recover.mapValues { (_, recovery) ->
                when (recovery) {
                    is Recovery.PatchJSONFile -> JSONFilePatch(
                        expandPath(recovery.path), recovery.keys, recovery.value, directory(WorkingDirectory.DEDICATED),
                    )
                }
            },
            requiredFiles = definition.requiresFiles.map(::expandPath),
            fileExists = files::exists,
            now = now,
        )
    }
}

/**
 * `recover.patchJSONFile` — sets one value deep in a JSON file that already exists, e.g. a CLI's
 * "I trust this folder" flag. True only when it changed the file, so a second failure is not
 * retried forever.
 */
internal class JSONFilePatch(
    private val path: String,
    private val keys: List<String>,
    private val value: JsonElement,
    private val cliDirectory: String,
) : Recovering {
    override fun recover(): Boolean {
        val file = Path(path)
        val document = runCatching {
            SystemFileSystem.source(file).buffered().use { Json.parseToJsonElement(it.readString()) } as? JsonObject
        }.getOrNull() ?: return false
        val keys = keys.map { it.replace("{{cliDirectory}}", cliDirectory) }
        val patched = set(value, keys, document) ?: return false
        return try {
            SystemFileSystem.sink(file).buffered().use { it.writeString(patched.toString()) }
            AppLog.probes.info("Patched $path so the CLI can run in the probe directory")
            true
        } catch (error: Exception) {
            AppLog.probes.error("Could not patch $path: ${error.message}")
            false
        }
    }

    /** The document with the value set, or null when it already had it or a key on the way is not an object. */
    private fun set(value: JsonElement, keys: List<String>, document: JsonObject): JsonObject? {
        val key = keys.firstOrNull() ?: return null
        if (keys.size == 1) return if (document[key] == value) null else JsonObject(document + (key to value))
        val child = when (val existing = document[key]) {
            null -> JsonObject(emptyMap())
            is JsonObject -> existing
            else -> return null
        }
        val updated = set(value, keys.drop(1), child) ?: return null
        return JsonObject(document + (key to updated))
    }
}
