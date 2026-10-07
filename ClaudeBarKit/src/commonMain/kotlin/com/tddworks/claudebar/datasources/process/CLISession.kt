package com.tddworks.claudebar.datasources.process

import com.tddworks.claudebar.datasources.CLICall
import com.tddworks.claudebar.datasources.CLIResult
import com.tddworks.claudebar.datasources.ProcessEnvironment
import com.tddworks.claudebar.diagnostics.AppLog
import kotlinx.atomicfu.locks.SynchronizedObject
import kotlinx.atomicfu.locks.synchronized
import org.kotlincrypto.hash.sha2.SHA256
import kotlin.random.Random

/**
 * What a CLI worker remembers of its session between runs (#132): the id it runs in, and
 * whether the installed CLI refused the session flags. In memory, one per worker — a
 * provider makes a worker per login, so each login keeps its own; a restart starts anew.
 */
internal class SessionMemory {
    private val lock = SynchronizedObject()
    private var rememberedId: String? = null
    private var refused = false

    val id: String? get() = synchronized(lock) { rememberedId }
    val isRefused: Boolean get() = synchronized(lock) { refused }

    fun remember(id: String) = synchronized(lock) { rememberedId = id }

    fun forget() = synchronized(lock) { rememberedId = null }

    /** Gives up on the session flags for this worker's lifetime. */
    fun refuse() = synchronized(lock) {
        refused = true
        rememberedId = null
    }
}

/**
 * Runs one CLI call inside the worker's session (#132): no remembered id → create one under a
 * fresh id and remember it; a remembered id → resume it; the CLI says it is gone → create
 * again; a non-zero exit naming a refused flag → the call's plain args from then on.
 */
internal class CLISessionRunner(
    private val call: CLICall,
    private val session: CLICall.Session,
    /** The call's working directory; null inherits. */
    private val directory: String?,
    private val makeExecutor: CLIExecutorFactory,
    private val memory: SessionMemory,
    /** A fresh session id — a random UUID in production. */
    private val nextId: () -> String = ::randomUuid,
) {
    suspend fun run(): CLIResult {
        if (memory.isRefused) return plain()
        session.id?.let { return runStable(stableId(it.stable, call.environment)) }
        val remembered = memory.id
        if (remembered != null) {
            val result = execute(session.resume, remembered)
            if (isRefused(result, session.unsupportedOn)) return giveUp()
            if (isGone(result.output, session.recreateOn)) {
                AppLog.probes.info("${call.cli}: the session is gone, creating a new one")
                memory.forget()
                return create()
            }
            return result
        }
        return create()
    }

    /** A stable session: created under its one id, resumed under it only when the CLI says the id is taken. */
    private suspend fun runStable(id: String): CLIResult {
        val result = execute(session.create, id)
        if (isRefused(result, session.unsupportedOn)) return giveUp()
        if (matches(result.output, session.resumeOn)) {
            AppLog.probes.info("${call.cli}: the session is kept, resuming it")
            return execute(session.resume, id)
        }
        return result
    }

    /** The session exists once the CLI boots, so the id is kept even if the screen goes on to fail parsing. */
    private suspend fun create(): CLIResult {
        val id = nextId()
        val result = execute(session.create, id)
        if (isRefused(result, session.unsupportedOn)) return giveUp()
        memory.remember(id)
        return result
    }

    private suspend fun giveUp(): CLIResult {
        AppLog.probes.info("${call.cli} refused the session flags, continuing without one session")
        memory.refuse()
        return plain()
    }

    private suspend fun plain(): CLIResult = execute(emptyList(), "")

    /** The call's own args, then the template's with `{{id}}` filled. */
    private suspend fun execute(template: List<String>, id: String): CLIResult =
        makeExecutor(call).execute(
            call.cli, call.args + template.map { it.replace("{{id}}", id) }, call.input, call.timeout,
            directory, call.autoResponses,
        )

    companion object {
        /**
         * One login's session id, the same forever: a name-based UUID from the definition's
         * text and the call's environment — another `CLAUDE_CONFIG_DIR`, another id.
         */
        fun stableId(text: String, environment: ProcessEnvironment): String {
            val seed = (listOf(text) + environment.set.entries.sortedBy { it.key }.map { "${it.key}=${it.value}" }).joinToString("\n")
            val bytes = SHA256().digest(seed.encodeToByteArray()).copyOf(16)
            bytes[6] = ((bytes[6].toInt() and 0x0F) or 0x50).toByte()
            bytes[8] = ((bytes[8].toInt() and 0x3F) or 0x80).toByte()
            return uuidText(bytes)
        }

        /** True when a run both failed and named a refused flag: a CLI build that rejects an option exits non-zero. */
        fun isRefused(result: CLIResult, tokens: List<String>): Boolean = result.exitCode != 0 && matches(result.output, tokens)

        fun isGone(output: String, tokens: List<String>): Boolean = matches(output, tokens)

        /** Matched as a ready marker is: a TUI places each word with a cursor move. */
        fun matches(output: String, tokens: List<String>): Boolean =
            tokens.isNotEmpty() && CLICompletionRule(tokens.map { CLICompletionRule.Marker(it) }).isReady(output)

        fun randomUuid(): String {
            val bytes = Random.nextBytes(16)
            bytes[6] = ((bytes[6].toInt() and 0x0F) or 0x40).toByte()
            bytes[8] = ((bytes[8].toInt() and 0x3F) or 0x80).toByte()
            return uuidText(bytes)
        }

        private fun uuidText(bytes: ByteArray): String {
            val hex = bytes.joinToString("") { (it.toInt() and 0xFF).toString(16).padStart(2, '0') }
            return "${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}"
        }
    }
}
