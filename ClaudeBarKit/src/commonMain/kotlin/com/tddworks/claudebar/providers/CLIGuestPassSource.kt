package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.CLIExecutor
import com.tddworks.claudebar.datasources.DefinitionError
import com.tddworks.claudebar.datasources.DefinitionJson
import com.tddworks.claudebar.datasources.ProcessEnvironment
import com.tddworks.claudebar.datasources.WorkingDirectory
import com.tddworks.claudebar.datasources.mapping.TextMapper
import com.tddworks.claudebar.datasources.process.DefaultCLIExecutor
import com.tddworks.claudebar.datasources.process.ProcessHost
import com.tddworks.claudebar.diagnostics.AppLog
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlin.coroutines.cancellation.CancellationException

/**
 * The definition's `guestPasses` block: the command its CLI hands out guest passes with, and
 * how to read the link and the count from what it shows (docs/providers/claude/design.md
 * § Guest passes). Every vendor fact is here, as data; the worker below names none.
 */
@Serializable
internal data class GuestPassCommand(
    /** The CLI's arguments — the definition's `cli`, at the person's *CLI location*. */
    val args: List<String> = emptyList(),
    val input: String = "",
    val timeout: Double = 20.0,
    /** Variables removed and added — `CLAUDEBAR_PROBE=1`, so ClaudeBar's own hook skips the session (#222). */
    val environment: ProcessEnvironment = ProcessEnvironment(),
    /** Prompt text → what to type when it appears. */
    val autoResponses: Map<String, String> = emptyMap(),
    /** Phrases, in any case, of which the screen must show one; none → any screen. */
    val succeededWhen: List<String> = emptyList(),
    /** The pattern the link to share matches. */
    val link: String,
    /** A pattern, in any case, whose first group is the passes left; none → an unknown count. */
    val count: String? = null,
    /** The CLI copies the link rather than printing it: read the clipboard when the screen shows none. */
    val clipboard: Boolean = false,
) {
    private val linkPattern: Regex get() = Regex(link)
    private val countPattern: Regex? get() = count?.let { Regex(it, RegexOption.IGNORE_CASE) }

    /** Whether the screen says the command worked. */
    fun succeeded(screen: String): Boolean {
        val lowered = screen.lowercase()
        return succeededWhen.isEmpty() || succeededWhen.any { lowered.contains(it.lowercase()) }
    }

    /** The first link in [text], or null. */
    fun link(text: String): String? = linkPattern.find(text)?.value

    /** The passes left [text] shows, or null when it shows none. */
    fun count(text: String): Long? = countPattern?.find(text)?.groupValues?.getOrNull(1)?.toLongOrNull()

    /** The guest pass a screen shows — the link required, the count when shown. */
    fun parse(output: String): GuestPass {
        val clean = TextMapper.stripANSI(output)
        val link = link(clean) ?: throw UsageError.ParseFailed("Could not find referral URL in output")
        return GuestPass(count(clean), link)
    }

    fun toJson(): JsonObject = DefinitionJson.encodeToJsonElement(serializer(), this).jsonObject

    companion object {
        /** Decodes the block and checks its patterns compile; a bad one is a `DefinitionError`. */
        fun from(json: JsonElement): GuestPassCommand {
            if (json !is JsonObject) throw DefinitionError("guestPasses is an object")
            if ("link" !in json) throw DefinitionError("guestPasses needs \"link\"")
            val command = try {
                DefinitionJson.decodeFromJsonElement(serializer(), json)
            } catch (error: Exception) {
                throw DefinitionError("guestPasses: ${error.message}")
            }
            for ((name, pattern) in listOf("link" to command.link, "count" to command.count)) {
                if (pattern != null && runCatching { Regex(pattern) }.isFailure) {
                    throw DefinitionError("guestPasses.$name is not a pattern: $pattern")
                }
            }
            return command
        }
    }
}

/** Where a CLI leaves what it copied — the Mac's pasteboard. */
internal fun interface Clipboard {
    /** The text on it, or null. */
    fun text(): String?
}

/**
 * The guest-passes worker: runs a definition's [GuestPassCommand] in a terminal and reads the
 * pass from the screen, or the link from the [clipboard] when the command copies it there.
 */
internal class CLIGuestPassSource(
    private val command: GuestPassCommand,
    /** The CLI to run — the provider's *CLI location* when the person chose one, read each time (#210). */
    private val cli: () -> String,
    private val executor: CLIExecutor,
    private val clipboard: Clipboard,
    /** The dedicated folder CLIs run in, so a folder-trust prompt never blocks the run. */
    private val workingDirectory: () -> String? = { null },
) : GuestPassSource {
    override suspend fun isAvailable(): Boolean {
        if (executor.locate(cli()) != null) return true
        AppLog.probes.error("Guest passes: CLI '${cli()}' not found in PATH")
        return false
    }

    override suspend fun fetch(): GuestPass {
        AppLog.probes.info("Guest passes: running ${cli()} ${command.args.firstOrNull().orEmpty()}")
        val output = try {
            executor.execute(cli(), command.args, command.input, command.timeout, workingDirectory(), command.autoResponses).output
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            AppLog.probes.error("Guest passes: the CLI failed: ${failure.message}")
            throw UsageError.ExecutionFailed(failure.message ?: failure.toString())
        }
        val clean = TextMapper.stripANSI(output)
        if (!command.succeeded(clean)) {
            AppLog.probes.error("Guest passes: unexpected output")
            throw UsageError.ParseFailed("Command did not indicate success")
        }
        // On the screen first, in case it shows the link; else where the command copied it.
        val link = command.link(clean) ?: clipboardLink()
        if (link == null) {
            AppLog.probes.error("Guest passes: could not find the referral link")
            throw UsageError.ParseFailed("Could not find referral URL")
        }
        val count = command.count(clean)
        AppLog.probes.info(if (count != null) "Guest passes: $count passes remaining" else "Guest passes: referral link obtained")
        return GuestPass(count, link)
    }

    private fun clipboardLink(): String? {
        if (!command.clipboard) return null
        return clipboard.text()?.let(command::link)?.also { AppLog.probes.info("Guest passes: got the referral link from the clipboard") }
    }

    companion object {
        /**
         * The engine's guest-pass runner on this Mac: each declaring definition's command, run in
         * a terminal with its environment, in the dedicated working directory.
         */
        fun runner(host: ProcessHost, clipboard: Clipboard): (cli: () -> String, command: GuestPassCommand) -> GuestPassSource =
            { cli, command ->
                val executor = DefaultCLIExecutor(host, command.environment.unset, command.environment.set)
                CLIGuestPassSource(command, cli, executor, clipboard) { host.directory(WorkingDirectory.DEDICATED) }
            }
    }
}
