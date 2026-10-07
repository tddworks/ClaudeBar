package com.tddworks.claudebar.datasources

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.encodeToJsonElement

/**
 * HOW TO GET THE BYTES — *Data fetching method*. A closed sum, one case per JSON tag
 * (`{ "http": { … } }`), because the decoder must know every tag and the picker is a fixed
 * list. A new protocol is a new case and one new worker.
 */
@Serializable(with = FetchSerializer::class)
internal sealed class Fetch {
    /** An HTTP request — the *API* choice. */
    data class Http(val request: HTTPRequest) : Fetch()

    /** HTTP requests in order, each able to use what an earlier one said: `"http": { "steps": […] }`. */
    data class HttpSteps(val steps: HTTPSteps) : Fetch()

    /** A JSON-RPC conversation with a CLI over stdin/stdout. */
    data class JsonRpc(val call: JSONRPCCall) : Fetch()

    /** A CLI run in a terminal, its screen captured — for a TUI. */
    data class Cli(val call: CLICall) : Fetch()

    /** A command run over pipes, its output and exit code read. */
    data class Command(val call: CommandCall) : Fetch()

    /** A file on this Mac that some tool keeps up to date — the *File* choice. */
    data class File(val call: FileCall) : Fetch()

    /** An app's own server on this Mac, found through its running process. */
    data class LocalServer(val call: LocalServerCall) : Fetch()

    /** A cloud's metrics, summed per dimension value. */
    data class CloudWatch(val call: CloudWatchCall) : Fetch()

    /** A folder some tool fills — the names in it. */
    data class Directory(val call: DirectoryCall) : Fetch()

    /** Rows of an app's own database, read-only. */
    data class Sqlite(val call: SQLiteCall) : Fetch()

    /** A script of the person's, run from its own folder with every setting in its environment. */
    data class Script(val call: ScriptCall) : Fetch()

    companion object {
        val tags = listOf("http", "jsonRpc", "cli", "command", "file", "localServer", "cloudWatch", "directory", "sqlite", "script")

        fun from(json: JsonElement): Fetch {
            val tagged = json as? JsonObject ?: throw DefinitionError("fetch is an object with one tag")
            val tag = tagged.singleTag(tags, "fetch")
            val payload = tagged.getValue(tag)
            return decoding("fetch.$tag") {
                when (tag) {
                    "http" -> if ((payload as? JsonObject)?.containsKey("steps") == true)
                        HttpSteps(DefinitionJson.decodeFromJsonElement(payload)) else Http(DefinitionJson.decodeFromJsonElement(payload))
                    "jsonRpc" -> JsonRpc(DefinitionJson.decodeFromJsonElement(payload))
                    "cli" -> Cli(DefinitionJson.decodeFromJsonElement(payload))
                    "command" -> Command(DefinitionJson.decodeFromJsonElement(payload))
                    "file" -> File(DefinitionJson.decodeFromJsonElement(payload))
                    "localServer" -> LocalServer(DefinitionJson.decodeFromJsonElement(payload))
                    "cloudWatch" -> CloudWatch(DefinitionJson.decodeFromJsonElement(payload))
                    "directory" -> Directory(DefinitionJson.decodeFromJsonElement(payload))
                    "sqlite" -> Sqlite(DefinitionJson.decodeFromJsonElement(payload))
                    else -> Script(DefinitionJson.decodeFromJsonElement(payload))
                }
            }
        }
    }

    fun toJson(): JsonElement = when (this) {
        is Http -> tagged("http", DefinitionJson.encodeToJsonElement(request))
        is HttpSteps -> tagged("http", DefinitionJson.encodeToJsonElement(steps))
        is JsonRpc -> tagged("jsonRpc", DefinitionJson.encodeToJsonElement(call))
        is Cli -> tagged("cli", DefinitionJson.encodeToJsonElement(call))
        is Command -> tagged("command", DefinitionJson.encodeToJsonElement(call))
        is File -> tagged("file", DefinitionJson.encodeToJsonElement(call))
        is LocalServer -> tagged("localServer", DefinitionJson.encodeToJsonElement(call))
        is CloudWatch -> tagged("cloudWatch", DefinitionJson.encodeToJsonElement(call))
        is Directory -> tagged("directory", DefinitionJson.encodeToJsonElement(call))
        is Sqlite -> tagged("sqlite", DefinitionJson.encodeToJsonElement(call))
        is Script -> tagged("script", DefinitionJson.encodeToJsonElement(call))
    }
}

internal object FetchSerializer : KSerializer<Fetch> {
    override val descriptor: SerialDescriptor = JsonElement.serializer().descriptor
    override fun deserialize(decoder: Decoder) = Fetch.from((decoder as JsonDecoder).decodeJsonElement())
    override fun serialize(encoder: Encoder, value: Fetch) = (encoder as JsonEncoder).encodeJsonElement(value.toJson())
}

internal fun tagged(tag: String, payload: JsonElement) = JsonObject(mapOf(tag to payload))

/** Decodes a part of a definition, turning any failure into a DefinitionError that says where. */
internal inline fun <T> decoding(where: String, decode: () -> T): T = try {
    decode()
} catch (error: DefinitionError) {
    throw error
} catch (error: Exception) {
    throw DefinitionError("$where: ${error.message}")
}

/** `{{name}}` placeholders in url, headers and body are filled from the credential at fetch time. */
@Serializable
internal data class HTTPRequest(
    val url: String,
    val method: String = "GET",
    val headers: Map<String, String> = emptyMap(),
    val body: String? = null,
    val timeout: Double = 15.0,
    /** The statuses that are an answer — part of the protocol. null: 2xx. */
    val acceptedStatuses: List<Int>? = null,
) {
    fun accepts(status: Int): Boolean = acceptedStatuses?.contains(status) ?: (status in 200..299)
}

/** Call A, then B with something A said; the response is every step's answer by name. At most eight steps. */
@Serializable
internal data class HTTPSteps(val steps: List<HTTPStep>) {
    init {
        require(steps.isNotEmpty() && steps.size <= LIMIT) { "http.steps needs 1 to $LIMIT steps" }
        require(steps.map { it.name }.toSet().size == steps.size) { "http.steps names must be unique" }
    }

    companion object {
        const val LIMIT = 8
    }
}

/** One request in `http.steps`. */
@Serializable
internal data class HTTPStep(
    val name: String,
    val request: HTTPRequest,
    val keep: Map<String, Keep> = emptyMap(),
    /** A failure leaves this step's values unknown instead of ending the fetch. */
    val optional: Boolean = false,
    /** Skipped when this value is already known. */
    val unless: String? = null,
    /** Tries again on a network failure or a 5xx, up to this many times in all. */
    val attempts: Int = 1,
    /** Values that may be missing: left out when they came out empty, instead of failing. */
    val dropEmpty: List<String> = emptyList(),
) {
    init {
        require(attempts in 1..3) { "a step's attempts is 1 to 3" }
    }

    /** A value read from a step's response, for later steps' `{{name}}`. */
    @Serializable(with = KeepSerializer::class)
    sealed class Keep {
        /** `"$.path"` in a JSON body, or a list of them — the first that answers. */
        data class Paths(val paths: List<String>) : Keep()

        /** `{ "pattern": "…" }` over the body's text; the first group. */
        data class Pattern(val pattern: String) : Keep()
    }
}

internal object KeepSerializer : KSerializer<HTTPStep.Keep> {
    override val descriptor: SerialDescriptor = JsonElement.serializer().descriptor
    override fun deserialize(decoder: Decoder): HTTPStep.Keep = when (val json = (decoder as JsonDecoder).decodeJsonElement()) {
        is JsonPrimitive -> HTTPStep.Keep.Paths(listOf(json.content))
        is JsonArray -> HTTPStep.Keep.Paths(json.map { (it as JsonPrimitive).content })
        is JsonObject -> HTTPStep.Keep.Pattern(json.requireString("pattern", "keep"))
    }

    override fun serialize(encoder: Encoder, value: HTTPStep.Keep) = (encoder as JsonEncoder).encodeJsonElement(
        when (value) {
            is HTTPStep.Keep.Paths -> if (value.paths.size == 1) JsonPrimitive(value.paths[0]) else JsonArray(value.paths.map(::JsonPrimitive))
            is HTTPStep.Keep.Pattern -> JsonObject(mapOf("pattern" to JsonPrimitive(value.pattern)))
        },
    )
}

/** Where a CLI runs. `dedicated` is ClaudeBar's own trusted folder, so a folder-trust prompt never blocks a fetch. */
@Serializable
internal enum class WorkingDirectory {
    @SerialName("dedicated") DEDICATED,
}

/** Variables to remove from, and add to, a CLI's environment. `{{token}}` in a value fills when a command starts. */
@Serializable
internal data class ProcessEnvironment(val unset: List<String> = emptyList(), val set: Map<String, String> = emptyMap())

/** Runs a command over pipes and reads what it printed; its exit code is reported, never ignored. */
@Serializable
internal data class CommandCall(
    val cli: String,
    val args: List<String> = emptyList(),
    /** Text written to the command's standard input — `"/usage\n/quit\n"`. */
    val input: String? = null,
    val timeout: Double = 20.0,
    val workingDirectory: WorkingDirectory? = null,
    val environment: ProcessEnvironment = ProcessEnvironment(),
)

/** Starts `cli args…`, sends the handshake in order, then `call`, and answers with the call's result. */
@Serializable
internal data class JSONRPCCall(
    val cli: String,
    val args: List<String> = emptyList(),
    val workingDirectory: WorkingDirectory? = null,
    val handshake: List<Step> = emptyList(),
    val call: String,
    val params: JsonElement? = null,
    val then: List<FollowUp> = emptyList(),
    val environment: ProcessEnvironment = ProcessEnvironment(),
) {
    @Serializable
    data class Step(
        /** A request, answered before the next step. */
        val request: String? = null,
        /** A notification, never answered. */
        val notify: String? = null,
        val params: JsonElement? = null,
    )

    /** A request after the call, its whole answer added to the response under `as`. */
    @Serializable
    data class FollowUp(val request: String, val params: JsonElement? = null, @SerialName("as") val name: String)
}

/** Runs `cli args…` in a terminal, types `input`, answers prompts from `autoResponses`, returns what the screen showed. */
@Serializable
internal data class CLICall(
    val cli: String,
    val args: List<String> = emptyList(),
    val input: String? = null,
    val timeout: Double = 20.0,
    val workingDirectory: WorkingDirectory? = null,
    /** Prompt text → what to type when it appears. */
    val autoResponses: Map<String, String> = emptyMap(),
    val environment: ProcessEnvironment = ProcessEnvironment(),
    val readyWhen: List<ReadyMarker> = emptyList(),
    val screen: Screen = Screen.RAW,
    /** Run in one session instead of a fresh one per run (#132). */
    val session: Session? = null,
    /** Seconds to let a TUI finish its startup paint before `input` is typed. */
    val inputDelay: Double? = null,
) {
    /** Text that means the screen has finished drawing: a phrase, or `{ "row": "…" }` that must end its row. */
    @Serializable(with = ReadyMarkerSerializer::class)
    data class ReadyMarker(val text: String, val endsRow: Boolean = false)

    /** How the captured output reaches the mapping. */
    @Serializable
    enum class Screen {
        /** The raw bytes, escape codes and all. */
        @SerialName("raw") RAW,

        /** Drawn by a terminal emulator first, so a TUI's cursor moves land where they put the text. */
        @SerialName("rendered") RENDERED,
    }

    /**
     * The one session every run shares (#132). Only the vendor's facts are data: the args that create
     * and resume it (`{{id}}` is the id), and the output that says it is gone or refused.
     */
    @Serializable
    data class Session(
        val id: Id? = null,
        val create: List<String>,
        val resume: List<String>,
        /** Output meaning a stable session's id is already taken — the same id is resumed. */
        val resumeOn: List<String> = emptyList(),
        /** Output meaning the session no longer exists — created again under a fresh id. */
        val recreateOn: List<String> = emptyList(),
        /** Output meaning the CLI rejected the session flags; honoured only with a non-zero exit. */
        val unsupportedOn: List<String> = emptyList(),
    ) {
        /** `{ "stable": "ClaudeBar Probe" }`: a UUID from this text and the call's environment — one per login. */
        @Serializable
        data class Id(val stable: String)
    }
}

internal object ReadyMarkerSerializer : KSerializer<CLICall.ReadyMarker> {
    override val descriptor: SerialDescriptor = JsonElement.serializer().descriptor
    override fun deserialize(decoder: Decoder): CLICall.ReadyMarker = when (val json = (decoder as JsonDecoder).decodeJsonElement()) {
        is JsonPrimitive -> CLICall.ReadyMarker(json.content)
        is JsonObject -> CLICall.ReadyMarker(json.requireString("row", "readyWhen"), endsRow = true)
        is JsonArray -> throw DefinitionError("readyWhen holds a phrase or { \"row\": … }")
    }

    override fun serialize(encoder: Encoder, value: CLICall.ReadyMarker) = (encoder as JsonEncoder).encodeJsonElement(
        if (value.endsRow) JsonObject(mapOf("row" to JsonPrimitive(value.text))) else JsonPrimitive(value.text),
    )
}

/** `~` and `${VAR:-default}` expand; a `*` or a list of paths reads the most recently changed file. */
@Serializable
internal data class FileCall(val path: PathPattern)

/** The names of the entries in a folder, sorted; ready while the folder exists. */
@Serializable
internal data class DirectoryCall(
    val path: PathPattern,
    /** A pattern an entry's name must match; every entry when absent. */
    val match: String? = null,
)

/** The rows an app's own database answers, each column as text; opened read-only, a changing query refused. */
@Serializable
internal data class SQLiteCall(val path: PathPattern, val query: String)

/**
 * Today's sums of `metrics` in `namespace`, one row per `dimension` value in each region, with the
 * person's own cloud profile. With `prices`, each row's unit prices come from the PriceCatalog.
 */
@Serializable
internal data class CloudWatchCall(
    val namespace: String,
    val dimension: String,
    val metrics: List<String>,
    /** Comma-separated — `"{{setting.regions}}"`. */
    val regions: String,
    /** A named profile, or blank for the default credentials. */
    val profile: String? = null,
    /** The service whose price list prices each dimension value. */
    val prices: String? = null,
) {
    /** The regions named, without blanks or a template left unfilled. */
    val regionList: List<String>
        get() = regions.split(',').map { it.trim() }.filter { it.isNotEmpty() && "{{" !in it }

    /** The profile, unless it was left blank. */
    val profileName: String?
        get() = profile?.trim()?.takeIf { it.isNotEmpty() && "{{" !in it }
}

/**
 * An app that serves its usage on 127.0.0.1: its process found by name, the values it was started
 * with read from its command line, its listening ports looked up, and the paths asked on each port.
 * Self-signed TLS is accepted on the loopback address only.
 */
@Serializable
internal data class LocalServerCall(
    /** What `cli.missing` names when no such process runs — "Antigravity". */
    val app: String,
    val process: Process,
    /** Name → a pattern over the command line; its first group is the value, filled as `{{name}}`. */
    val values: Map<String, String> = emptyMap(),
    /** Values the server can't be asked without: missing is *Key needed*. */
    val required: List<String> = emptyList(),
    /** Asked in order on every listening port; the first 200 answers. */
    val paths: List<String>,
    /** A value holding a port also asked over plain HTTP, last. */
    val plainHTTPPort: String? = null,
    val method: String = "POST",
    val headers: Map<String, String> = emptyMap(),
    val body: String? = null,
    val timeout: Double = 8.0,
) {
    /** Which process: its name contains one of `names`, its command line matches one of `match` (any, when empty). */
    @Serializable
    data class Process(val names: List<String>, val match: List<String> = emptyList())
}

/**
 * Runs `run` with `/bin/sh` from `folder`. `environment` fills like any definition string; each of
 * `secrets` is a setting read from the login's vault, so a script may take several keys.
 */
@Serializable
internal data class ScriptCall(
    val run: String,
    val folder: String,
    val environment: Map<String, String> = emptyMap(),
    /** Environment variable → the vault setting whose value it takes. */
    val secrets: Map<String, String> = emptyMap(),
    val timeout: Double = 10.0,
) {
    /** The script's own path: `run` in `folder`, unless it is absolute. */
    val path: String
        get() = if (run.startsWith("/")) run else folder.trimEnd('/') + "/" + run.removePrefix("./")
}
