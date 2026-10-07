package com.tddworks.claudebar.datasources

import com.tddworks.claudebar.datasources.lookup.CredentialLookup
import com.tddworks.claudebar.datasources.lookup.JSONFileCredential
import com.tddworks.claudebar.datasources.mapping.ErrorRef
import com.tddworks.claudebar.datasources.mapping.Mapping
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.encodeToJsonElement

/**
 * One data source as data — the JSON a provider definition lists under `dataSources`. No
 * behaviour: `DataSources.make` turns it into a `DataSource` that fetches.
 */
internal data class DataSourceDefinition(
    /** What the person picks — `rpc`, `api`, `cli` … — and the value of `<id>.probeMode`. */
    val kind: String,
    val label: String? = null,
    val summary: String? = null,
    /** One sentence Settings shows while this data source is picked. */
    val note: String? = null,
    /** Only ever reached as another one's fallback. */
    val hidden: Boolean = false,
    val credential: CredentialLookup? = null,
    val fetch: Fetch,
    val mapping: Mapping,
    /** The data source to try when this one fails, optionally only while a setting allows it. */
    val fallback: Fallback? = null,
    /** Hand-offs by failure: `{ "subscriptionRequired": "cliCost" }`, tried before `fallback`. */
    val fallbackOn: Map<String, String> = emptyMap(),
    /** Serve the last usage this long instead of fetching again; also the background refresh floor. */
    val cache: Cache? = null,
    /** JSON files the mapping may read. */
    val context: Map<String, JSONFileCredential> = emptyMap(),
    /** What to do once when the mapping reports a failure, then try again. */
    val recover: Map<String, Recovery> = emptyMap(),
    /** Files that must exist before anything runs (#216); missing is *Key needed*. */
    val requiresFiles: List<String> = emptyList(),
    /** The credential must belong to this account, before and after the fetch. */
    val identity: Identity? = null,
    /** A background refresh must not run this until one explicit refresh has succeeded (#216). */
    val verifyBeforeBackground: Boolean = false,
    /** What a held-back refresh says until then. */
    val unverifiedMessage: String? = null,
    /** What a fact a worker reported means here, in the reasons the screen prints. */
    val errors: Map<ErrorFact, ErrorRef> = emptyMap(),
) {
    /** What a failure a worker reported means here: the definition's word for its fact, else the worker's. */
    fun reason(failure: ReportedFailure): UsageError {
        val fact = failure.fact ?: return failure.reason
        val meaning = errors[fact] ?: fact.broader?.let { errors[it] }
        return meaning?.usageError ?: failure.reason
    }

    fun toJson(): JsonObject = JsonObject(buildMap {
        put("kind", JsonPrimitive(kind))
        label?.let { put("label", JsonPrimitive(it)) }
        summary?.let { put("summary", JsonPrimitive(it)) }
        note?.let { put("note", JsonPrimitive(it)) }
        if (hidden) put("hidden", JsonPrimitive(true))
        credential?.let { put("credential", it.toJson()) }
        put("fetch", fetch.toJson())
        put("mapping", mapping.toJson())
        fallback?.let { put("fallback", it.toJson()) }
        if (fallbackOn.isNotEmpty()) put("fallbackOn", JsonObject(fallbackOn.mapValues { JsonPrimitive(it.value) }))
        cache?.let { put("cache", JsonObject(mapOf("ttl" to JsonPrimitive(it.ttl)))) }
        if (context.isNotEmpty()) put("context", JsonObject(context.mapValues { it.value.toJson() }))
        if (recover.isNotEmpty()) put("recover", JsonObject(recover.mapValues { it.value.toJson() }))
        if (requiresFiles.isNotEmpty()) put("requiresFiles", JsonArray(requiresFiles.map(::JsonPrimitive)))
        identity?.let { put("identity", it.toJson()) }
        if (verifyBeforeBackground) put("verifyBeforeBackground", JsonPrimitive(true))
        unverifiedMessage?.let { put("unverifiedMessage", JsonPrimitive(it)) }
        if (errors.isNotEmpty()) {
            put("errors", JsonObject(errors.entries.associate { it.key.name to DefinitionJson.encodeToJsonElement(it.value) }))
        }
    })

    companion object {
        fun from(json: JsonElement): DataSourceDefinition {
            val o = json as? JsonObject ?: throw DefinitionError("a data source is an object")
            val kind = o.requireString("kind", "data source")
            return decoding("dataSources.$kind") {
                DataSourceDefinition(
                    kind = kind,
                    label = o.string("label"),
                    summary = o.string("summary"),
                    note = o.string("note"),
                    hidden = o.bool("hidden") ?: false,
                    credential = o["credential"]?.let(CredentialLookup::from),
                    fetch = Fetch.from(o["fetch"] ?: throw DefinitionError("needs \"fetch\"")),
                    mapping = Mapping.from(o["mapping"] ?: throw DefinitionError("needs \"mapping\"")),
                    fallback = o["fallback"]?.let(Fallback::from),
                    fallbackOn = o.stringMap("fallbackOn") ?: emptyMap(),
                    cache = (o["cache"] as? JsonObject)?.let { Cache(it.double("ttl") ?: throw DefinitionError("cache needs \"ttl\"")) },
                    context = (o["context"] as? JsonObject)?.mapValues { JSONFileCredential.from(it.value) } ?: emptyMap(),
                    recover = (o["recover"] as? JsonObject)?.mapValues { Recovery.from(it.value) } ?: emptyMap(),
                    requiresFiles = o.strings("requiresFiles") ?: emptyList(),
                    identity = o["identity"]?.let(Identity::from),
                    verifyBeforeBackground = o.bool("verifyBeforeBackground") ?: false,
                    unverifiedMessage = o.string("unverifiedMessage"),
                    errors = (o["errors"] as? JsonObject)?.entries?.associate { (name, ref) ->
                        val fact = ErrorFact.parse(name) ?: throw DefinitionError(
                            "Unknown error fact '$name': use http.<status>, http.default, cli.missing, cli.nonzero or cli.failed",
                        )
                        fact to DefinitionJson.decodeFromJsonElement<ErrorRef>(ref)
                    } ?: emptyMap(),
                )
            }
        }
    }

    // A definition adapted to one login, as data: an RFC 7396 merge patch for what differs, then
    // the login's values for `{{account.x}}`. Written once; nothing is copied per login.

    /** The definition with [patch] merged in (RFC 7396). */
    fun patched(patch: JsonElement): DataSourceDefinition = from(toJson().merged(patch))

    /** Every `{{<scope>.<name>}}` in its strings replaced by `values[name]`; other placeholders stay. */
    fun filled(values: Map<String, String>, scope: String): DataSourceDefinition =
        from(toJson().mapStrings { Placeholders.fill(it, values, scope) })

    /** The `{{<scope>.<name>}}` names still in the definition, sorted. */
    fun unfilled(scope: String): List<String> {
        val names = sortedSetOf<String>()
        toJson().mapStrings { names += Placeholders.names(it, scope); it }
        return names.toList()
    }
}

/** `"fallback": "tty"`, or `{ "to": "cli", "enabledBySetting": "cliFallbackEnabled" }` — on unless the setting says no. */
internal data class Fallback(val to: String, val enabledBySetting: String? = null) {
    fun toJson(): JsonElement = if (enabledBySetting == null) JsonPrimitive(to)
    else JsonObject(mapOf("to" to JsonPrimitive(to), "enabledBySetting" to JsonPrimitive(enabledBySetting)))

    companion object {
        fun from(json: JsonElement): Fallback = when (json) {
            is JsonPrimitive -> Fallback(json.content)
            is JsonObject -> Fallback(json.requireString("to", "fallback"), json.string("enabledBySetting"))
            else -> throw DefinitionError("fallback is a data source's kind or { \"to\": … }")
        }
    }
}

/** How long a fetched usage is served again, in seconds. */
internal data class Cache(val ttl: Double)

/** A fix tried once when the mapping reports a failure. */
internal sealed class Recovery {
    /** Sets one value deep inside a JSON file that already exists — a CLI's "trusted folder" flag; keys may hold `{{cliDirectory}}`. */
    data class PatchJSONFile(val path: String, val keys: List<String>, val value: JsonElement) : Recovery()

    fun toJson(): JsonElement = when (this) {
        is PatchJSONFile -> tagged("patchJSONFile", JsonObject(mapOf(
            "path" to JsonPrimitive(path), "keys" to JsonArray(keys.map(::JsonPrimitive)), "value" to value,
        )))
    }

    companion object {
        fun from(json: JsonElement): Recovery {
            val patch = (json as? JsonObject)?.get("patchJSONFile") as? JsonObject
                ?: throw DefinitionError("recover needs { \"patchJSONFile\": … }")
            return PatchJSONFile(
                patch.requireString("path", "patchJSONFile"),
                patch.strings("keys") ?: throw DefinitionError("patchJSONFile needs \"keys\""),
                patch["value"] ?: throw DefinitionError("patchJSONFile needs \"value\""),
            )
        }
    }
}

/**
 * Whose login this must be: the value [field] points at equals [equals], or the session is
 * treated as expired with [hint] — a folder signed in to another account never reports that
 * account's usage as this one's.
 */
internal data class Identity(val field: IdentityField, val equals: String, val hint: String? = null) {
    fun toJson(): JsonElement = JsonObject(buildMap {
        put("field", JsonPrimitive(field.path))
        put("equals", JsonPrimitive(equals))
        hint?.let { put("hint", JsonPrimitive(it)) }
    })

    companion object {
        fun from(json: JsonElement): Identity {
            val o = json as? JsonObject ?: throw DefinitionError("identity is an object")
            return Identity(IdentityField.parse(o.requireString("field", "identity")), o.requireString("equals", "identity"), o.string("hint"))
        }
    }
}

/**
 * A field that identifies a login, read without asking the vendor: `"account"` or
 * `"$credential.account"` — a credential value; `"$context.account.email"` — a context file's field.
 */
internal sealed class IdentityField {
    data class CredentialValue(val name: String) : IdentityField()
    data class ContextValue(val file: String, val field: String) : IdentityField()

    /** As a definition writes it; a credential value keeps the bare name. */
    val path: String
        get() = when (this) {
            is CredentialValue -> name
            is ContextValue -> "\$context.${this.file}.${this.field}"
        }

    companion object {
        fun parse(path: String): IdentityField = when {
            path.startsWith("\$context.") -> {
                val parts = path.removePrefix("\$context.").split('.')
                if (parts.size != 2 || parts.any { it.isEmpty() }) throw DefinitionError("$path: expected \$context.<file>.<field>")
                ContextValue(parts[0], parts[1])
            }
            path.startsWith("\$credential.") -> CredentialValue(path.removePrefix("\$credential."))
            else -> CredentialValue(path)
        }
    }
}
