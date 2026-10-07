package com.tddworks.claudebar.datasources.process

import com.tddworks.claudebar.datasources.CLICall
import com.tddworks.claudebar.datasources.CLIExecutor
import com.tddworks.claudebar.datasources.CLIResult
import com.tddworks.claudebar.datasources.CommandCall
import com.tddworks.claudebar.datasources.Credential
import com.tddworks.claudebar.datasources.ErrorFact
import com.tddworks.claudebar.datasources.Fetching
import com.tddworks.claudebar.datasources.JSONRPCCall
import com.tddworks.claudebar.datasources.ProcessEnvironment
import com.tddworks.claudebar.datasources.RPCTransport
import com.tddworks.claudebar.datasources.ReportedFailure
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.datasources.ScriptCall
import com.tddworks.claudebar.datasources.SecretStore
import com.tddworks.claudebar.datasources.Template
import com.tddworks.claudebar.datasources.WorkingDirectory
import com.tddworks.claudebar.diagnostics.AppLog
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.longOrNull

/** The executor for one terminal call: its environment changes and ready markers. */
internal typealias CLIExecutorFactory = (CLICall) -> CLIExecutor

/** The executor for a piped command with this environment. */
internal typealias CommandExecutorFactory = (ProcessEnvironment) -> CLIExecutor

/**
 * `cli` — drives a CLI in a terminal and answers with what the screen showed, drawn by a
 * terminal emulator first when the call asks for `rendered`.
 */
internal class CLIFetcher(
    val call: CLICall,
    private val makeExecutor: CLIExecutorFactory,
    /** Where a call's `workingDirectory` is on this Mac. */
    private val directory: (WorkingDirectory) -> String,
) : Fetching {
    /** The session this worker runs in — one per worker, and a provider makes a worker per login (#132). */
    private val session = SessionMemory()

    override fun isReady(): Boolean = makeExecutor(call).locate(call.cli) != null

    override suspend fun fetch(credential: Credential?): Response {
        val folder = call.workingDirectory?.let(directory)
        val result: CLIResult = try {
            val plan = call.session
            if (plan != null) {
                CLISessionRunner(call, plan, folder, makeExecutor, session).run()
            } else {
                makeExecutor(call).execute(call.cli, call.args, call.input, call.timeout, folder, call.autoResponses)
            }
        } catch (missing: UsageError.CliNotFound) {
            // A fact, so the definition's `errors["cli.missing"]` words it.
            throw CLIMissingError(call.cli)
        } catch (error: UsageError) {
            throw error
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            throw UsageError.ExecutionFailed(error.message ?: error.toString())
        }
        AppLog.probes.debug("${call.cli} screen captured (${result.output.length} chars)")
        return when (call.screen) {
            CLICall.Screen.RAW -> Response(result.output)
            CLICall.Screen.RENDERED -> Response(TerminalRenderer(cols = 160, rows = 50).render(result.output))
        }
    }

    companion object {
        /** The real terminal: a [DefaultCLIExecutor] with the call's environment changes and ready markers. */
        fun system(host: ProcessHost): CLIExecutorFactory = { call ->
            DefaultCLIExecutor(
                host = host,
                environmentExclusions = call.environment.unset,
                environmentAdditions = call.environment.set,
                completionRule = if (call.readyWhen.isEmpty()) null
                else CLICompletionRule(call.readyWhen.map { CLICompletionRule.Marker(it.text, it.endsRow) }),
                inputDelay = call.inputDelay ?: 0.4,
            )
        }
    }
}

/**
 * `command` — runs a command over pipes and answers with what it printed. A missing CLI, a
 * non-zero exit and a failed launch are facts the definition's `errors` may word.
 */
internal class CommandFetcher(
    val call: CommandCall,
    private val makeExecutor: CommandExecutorFactory,
    private val directory: (WorkingDirectory) -> String,
) : Fetching {
    override fun isReady(): Boolean = makeExecutor(call.environment).locate(call.cli) != null

    override suspend fun fetch(credential: Credential?): Response {
        val executor = makeExecutor(call.environment.filled(credential))
        if (executor.locate(call.cli) == null) throw CLIMissingError(call.cli)
        val result = try {
            executor.execute(call.cli, call.args, call.input, call.timeout, call.workingDirectory?.let(directory), emptyMap())
        } catch (gone: UsageError.CliNotFound) {
            // Gone between the check and the run.
            throw CLIMissingError(call.cli)
        } catch (error: UsageError) {
            throw error
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            AppLog.probes.error("${call.cli} could not start")
            throw CLILaunchError(call.cli)
        }
        if (result.exitCode != 0) {
            AppLog.probes.error("${call.cli} exited with ${result.exitCode}")
            throw CLIExitError(call.cli, result.exitCode)
        }
        AppLog.probes.debug("${call.cli} answered (${result.output.length} chars)")
        return Response(result.output)
    }

    companion object {
        /** Plain pipes, with a PATH that finds the tools a login shell would. */
        fun system(host: ProcessHost): CommandExecutorFactory = { environment -> PipeCLIExecutor(host, environment) }
    }
}

/**
 * `script` — the person's own script, run with `/bin/sh` from its folder, its environment the
 * definition's values and the secrets it names from the login's vault. Answers with what it
 * printed; a non-zero exit is a fact, as for `command`.
 */
internal class ScriptFetcher(
    val call: ScriptCall,
    private val providerId: String,
    private val secrets: SecretStore?,
    private val makeExecutor: CommandExecutorFactory,
    private val files: MachineFiles,
) : Fetching {
    override fun isReady(): Boolean = files.exists(call.path)

    override suspend fun fetch(credential: Credential?): Response {
        // A setting never set and without a default still reads `{{setting.x}}`: it isn't passed.
        val set = call.environment.filterValues { "{{setting." !in it }.toMutableMap()
        for ((variable, setting) in call.secrets) {
            secrets?.secret(setting, providerId)?.let { set[variable] = it }
        }
        val executor = makeExecutor(ProcessEnvironment(set = set))
        val name = call.run.trimEnd('/').substringAfterLast('/')
        if (!isReady()) throw CLIMissingError(name)
        val result = try {
            executor.execute("/bin/sh", listOf("-c", call.path), null, call.timeout, call.folder.trimEnd('/').ifEmpty { "/" }, emptyMap())
        } catch (error: UsageError) {
            throw error
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            AppLog.probes.error("$name could not start")
            throw CLILaunchError(name)
        }
        if (result.exitCode != 0) {
            AppLog.probes.error("$name exited with ${result.exitCode}")
            throw CLIExitError(name, result.exitCode)
        }
        return Response(result.output)
    }
}

/** `jsonRpc` — starts the CLI, sends the handshake, then the call, and answers with the call's whole message. */
internal class JSONRPCFetcher(
    val call: JSONRPCCall,
    private val cliExecutor: CLIExecutor,
    private val makeTransport: RPCTransportFactory,
    private val directory: (WorkingDirectory) -> String,
    /** The app's environment, changed per call as the definition asks. */
    private val environment: () -> Map<String, String>,
) : Fetching {
    override fun isReady(): Boolean {
        if (cliExecutor.locate(call.cli) != null) return true
        AppLog.probes.error("'${call.cli}' not found in PATH")
        return false
    }

    override suspend fun fetch(credential: Credential?): Response {
        val transport = makeTransport.open(call.cli, call.args, environment(call.environment), call.workingDirectory?.let(directory))
        try {
            val session = RPCSession(transport)
            for (step in call.handshake) {
                val request = step.request
                val notification = step.notify
                if (request != null) session.request(request, step.params) else if (notification != null) session.notify(notification, step.params)
            }
            val message = session.request(call.call, call.params).toMutableMap()
            for (followUp in call.then) message[followUp.name] = session.request(followUp.request, followUp.params)
            AppLog.probes.debug("${call.cli} ${call.call} answered")
            return Response(body = Json.encodeToString(JsonObject.serializer(), JsonObject(message)).encodeToByteArray())
        } finally {
            transport.close()
        }
    }

    /** The app's environment changed as the call asks, or null to inherit it untouched; the app's own is never mutated. */
    fun environment(change: ProcessEnvironment): Map<String, String>? {
        if (change.unset.isEmpty() && change.set.isEmpty()) return null
        val variables = environment().toMutableMap()
        change.unset.forEach(variables::remove)
        variables.putAll(change.set)
        return variables
    }
}

/** Newline-delimited JSON-RPC over a transport: numbered requests, answers matched by id, notifications skipped. */
internal class RPCSession(private val transport: RPCTransport) {
    private var nextId = 1

    suspend fun request(method: String, params: JsonElement?): JsonObject {
        val id = nextId++
        send(JsonObject(mapOf("id" to JsonPrimitive(id), "method" to JsonPrimitive(method), "params" to (params ?: JsonObject(emptyMap())))))
        while (true) {
            val data = transport.receive()
            val message = runCatching { Json.parseToJsonElement(data.decodeToString()) as? JsonObject }.getOrNull() ?: continue
            if (integer(message["id"]) != id.toLong()) continue
            val error = message["error"] as? JsonObject
            val text = (error?.get("message") as? JsonPrimitive)?.takeIf { it.isString }?.content
            if (text != null) throw UsageError.ExecutionFailed("RPC error: $text")
            return message
        }
    }

    fun notify(method: String, params: JsonElement?) {
        send(JsonObject(mapOf("method" to JsonPrimitive(method), "params" to (params ?: JsonObject(emptyMap())))))
    }

    private fun send(payload: JsonObject) = transport.send(Json.encodeToString(JsonObject.serializer(), payload).encodeToByteArray())

    /** An id as Foundation reads `as? Int`: a whole number, written as an integer or not. */
    private fun integer(value: JsonElement?): Long? {
        val primitive = value as? JsonPrimitive ?: return null
        if (primitive.isString) return null
        primitive.longOrNull?.let { return it }
        return primitive.doubleOrNull?.takeIf { it == kotlin.math.floor(it) }?.toLong()
    }
}

/** A command whose CLI isn't on this Mac — `errors["cli.missing"]`. */
internal class CLIMissingError(val cli: String) : Exception("CLI not found: $cli"), ReportedFailure {
    override val fact: ErrorFact get() = ErrorFact.CliMissing
    override val reason: UsageError get() = UsageError.CliNotFound(cli)
}

/** A command that exited non-zero — `errors["cli.nonzero"]`. */
internal class CLIExitError(val cli: String, val exitCode: Int) : Exception("`$cli` exited with code $exitCode"), ReportedFailure {
    override val fact: ErrorFact get() = ErrorFact.CliNonzero
    override val reason: UsageError get() = UsageError.ExecutionFailed("`$cli` exited with code $exitCode")
}

/** A command that could not be started — `errors["cli.failed"]`. */
internal class CLILaunchError(val cli: String) : Exception("`$cli` could not be started"), ReportedFailure {
    override val fact: ErrorFact get() = ErrorFact.CliFailed
    override val reason: UsageError get() = UsageError.ExecutionFailed("`$cli` could not be started")
}

/** The environment with `{{token}}` and the like filled in; a value naming something unknown means the key is missing. */
internal fun ProcessEnvironment.filled(credential: Credential?): ProcessEnvironment =
    ProcessEnvironment(unset, set.mapValues { (_, template) -> Template.fill(template, credential) ?: throw UsageError.AuthenticationRequired })
