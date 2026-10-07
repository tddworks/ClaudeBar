package com.tddworks.claudebar.datasources.process

import com.tddworks.claudebar.datasources.CLIExecutor
import com.tddworks.claudebar.datasources.Credential
import com.tddworks.claudebar.datasources.Fetching
import com.tddworks.claudebar.datasources.HttpCall
import com.tddworks.claudebar.datasources.LocalServerCall
import com.tddworks.claudebar.datasources.NetworkClient
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.datasources.Template
import com.tddworks.claudebar.diagnostics.AppLog
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.coroutines.CancellationException

/**
 * `localServer` — an app's own server on this Mac. Its process is found by name and command
 * line, the values it started with are read from that command line, and the declared paths
 * are asked on its listening ports, on 127.0.0.1 only.
 */
internal class LocalServerFetcher(
    val call: LocalServerCall,
    /** Runs `pgrep` and `lsof`. */
    private val commands: CLIExecutor,
    /** The loopback client: self-signed TLS accepted on 127.0.0.1 only. */
    private val network: NetworkClient,
    /** The executable paths running now — read without starting a process, so readiness stays cheap. */
    private val processPaths: () -> List<String>,
) : Fetching {
    /** Running, as far as its executable's path can tell. */
    override fun isReady(): Boolean = processPaths().any { isApp(it, call.process) }

    override suspend fun fetch(credential: Credential?): Response {
        val query = processQuery(call.process)
        // An empty pgrep result surfaces as a runner timeout, not "not found".
        val listing = outputOrEmpty { commands.execute(query[0], query.drop(1), null, call.timeout, null, emptyMap()).output }
        val line = listing.split(newlines).map { it.trim(' ', '\t') }.firstOrNull { isApp(it, call.process) }
        val pid = line?.split(' ')?.firstOrNull { it.isNotEmpty() }?.toIntOrNull()
        if (line == null || pid == null) {
            AppLog.probes.info("${call.app} isn't running")
            throw CLIMissingError(call.app)
        }

        var values = credential ?: Credential(emptyMap())
        for ((name, pattern) in call.values) {
            val value = firstGroup(pattern, line)
            if (value != null && values[name] == null) values = values.with(name, value)
        }
        for (name in call.required) {
            if (values[name] == null) {
                // Never the value; only that it is missing.
                AppLog.probes.error("${call.app} is running without its $name")
                throw UsageError.AuthenticationRequired
            }
        }

        val lsof = outputOrEmpty {
            commands.execute("/usr/sbin/lsof", listOf("-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p", pid.toString()), null, call.timeout, null, emptyMap()).output
        }
        val tries = listeningPorts(lsof).map { "https" to it }.toMutableList()
        call.plainHTTPPort?.let { name -> values[name]?.toIntOrNull()?.let { tries += "http" to it } }
        if (tries.isEmpty()) throw UsageError.ExecutionFailed("${call.app} isn't listening on any port")

        for ((scheme, port) in tries) {
            for (path in call.paths) {
                ask("$scheme://127.0.0.1:$port$path", values)?.let { return it }
            }
        }
        throw UsageError.ExecutionFailed("Could not connect to ${call.app}")
    }

    /** One request; null unless it answered 200. */
    private suspend fun ask(address: String, values: Credential): Response? {
        val headers = mutableMapOf<String, String>()
        for ((name, template) in call.headers) headers[name] = Template.fill(template, values) ?: return null
        val body = call.body?.let { Template.fill(it, values) ?: return null }
        val response = try {
            network.send(HttpCall(address, call.method, headers, body?.encodeToByteArray(), call.timeout))
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failed: Exception) {
            return null
        }
        if (response.status != 200) return null
        return Response(status = 200, headers = response.headers, body = response.body)
    }

    private suspend fun outputOrEmpty(run: suspend () -> String): String = try {
        run()
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (failed: Exception) {
        ""
    }

    companion object {
        /** What Foundation counts as a line break. */
        private val newlines = Regex("[\n\u000B\u000C\r\u0085  ]")

        /** `pgrep -lf name|name…` — every process whose command line names one. */
        fun processQuery(process: LocalServerCall.Process): List<String> =
            listOf("/usr/bin/pgrep", "-lf", process.names.joinToString("|"))

        fun isApp(commandLine: String, process: LocalServerCall.Process): Boolean {
            val lower = commandLine.lowercase()
            if (process.names.none { it.lowercase() in lower }) return false
            return process.match.isEmpty() || process.match.any { pattern ->
                runCatching { Regex(pattern).containsMatchIn(lower) }.getOrDefault(false)
            }
        }

        fun firstGroup(pattern: String, text: String): String? =
            runCatching { Regex(pattern, RegexOption.IGNORE_CASE).find(text)?.groups?.get(1)?.value }.getOrNull()

        /** `… TCP 127.0.0.1:53421 (LISTEN)` → 53421, each once, in order. */
        fun listeningPorts(lsof: String): List<Int> =
            Regex(""":(\d+)\s+\(LISTEN\)""").findAll(lsof).mapNotNull { it.groupValues[1].toIntOrNull() }.toSet().sorted()
    }
}
