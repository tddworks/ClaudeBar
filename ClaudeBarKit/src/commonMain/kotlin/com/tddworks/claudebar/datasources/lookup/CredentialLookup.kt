package com.tddworks.claudebar.datasources.lookup

import com.tddworks.claudebar.datasources.CLICall
import com.tddworks.claudebar.datasources.DefinitionError
import com.tddworks.claudebar.datasources.DefinitionJson
import com.tddworks.claudebar.datasources.PathPattern
import com.tddworks.claudebar.datasources.bool
import com.tddworks.claudebar.datasources.decoding
import com.tddworks.claudebar.datasources.requireString
import com.tddworks.claudebar.datasources.singleTag
import com.tddworks.claudebar.datasources.stringMap
import com.tddworks.claudebar.datasources.strings
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
 * WHOSE KEY — the screen's *Key lookup order*. A closed sum, one case per JSON tag; `firstOf`
 * is the order itself, and `refresh` keeps an OAuth token fresh and writes it back where it
 * came from.
 */
@Serializable(with = CredentialLookupSerializer::class)
internal sealed class CredentialLookup {
    /** An environment variable holds the token; `loginShell` also asks the person's login shell (#170). */
    data class Environment(val name: String, val loginShell: Boolean = false) : CredentialLookup()

    /** A JSON file on this Mac holds the token and its companions. */
    data class JsonFile(val file: JSONFileCredential) : CredentialLookup()

    /** A generic-password Keychain item whose password is JSON (or the token itself, with `"token": "$"`). */
    data class Keychain(val item: KeychainCredential) : CredentialLookup()

    /** A key the person gave ClaudeBar (*API KEY*), kept in its vault. */
    data class Setting(val name: String) : CredentialLookup()

    /** Cookies of a site the person is signed in to in a browser — *COOKIE SOURCE*. */
    data class BrowserCookies(val query: BrowserCookieCredential) : CredentialLookup()

    /** Values a browser keeps for a site, all from one profile. */
    data class BrowserStorage(val query: BrowserStorageCredential) : CredentialLookup()

    /** A row of another app's own SQLite database, read only. */
    data class Sqlite(val database: SQLiteCredential) : CredentialLookup()

    /** A lookup that answers only when its values match, with fixed values added. */
    data class Refined(val base: CredentialLookup, val refinement: Refinement) : CredentialLookup()

    /** The first lookup that answers wins. */
    data class FirstOf(val lookups: List<CredentialLookup>) : CredentialLookup()

    /** A lookup whose token is kept fresh: by an OAuth 2 refresh, or by the CLI that owns it. */
    data class Refreshing(val base: CredentialLookup, val refresh: CredentialRefresh) : CredentialLookup()

    /** *KEY LOOKUP ORDER* — where the key is looked for, as a person would find it. Never a value. */
    val lookupOrder: List<String>
        get() = when (this) {
            is Environment -> listOf(if (loginShell) "$$name (also your login shell)" else "$$name")
            is JsonFile -> file.path.places
            is Keychain -> listOf("Keychain “${item.service}”")
            is Setting -> listOf("API key saved in ClaudeBar")
            is BrowserCookies -> listOf("Browser cookies for ${query.domains.firstOrNull() ?: "the site"}")
            is BrowserStorage -> listOf("Browser storage · ${query.site}")
            is Sqlite -> database.path.places
            is Refined -> base.lookupOrder
            is FirstOf -> lookups.flatMap { it.lookupOrder }
            is Refreshing -> base.lookupOrder
        }

    /** What to do when no key answers, or it can no longer be refreshed. */
    val hint: String?
        get() = when (this) {
            is Refreshing -> refresh.hint ?: base.hint
            is FirstOf -> lookups.firstNotNullOfOrNull { it.hint }
            is Sqlite -> database.hint
            is Refined -> base.hint
            else -> null
        }

    fun toJson(): JsonElement = JsonObject(fields())

    private fun fields(): Map<String, JsonElement> = when (this) {
        is Environment -> buildMap {
            put("environment", JsonPrimitive(name))
            if (loginShell) put("loginShell", JsonPrimitive(true))
        }
        is JsonFile -> mapOf("jsonFile" to file.toJson())
        is Keychain -> mapOf("keychain" to item.toJson())
        is Setting -> mapOf("setting" to JsonPrimitive(name))
        is BrowserCookies -> mapOf("browserCookies" to DefinitionJson.encodeToJsonElement(query))
        is BrowserStorage -> mapOf("browserStorage" to DefinitionJson.encodeToJsonElement(query))
        is Sqlite -> mapOf("sqlite" to DefinitionJson.encodeToJsonElement(database))
        is Refined -> base.fields() + buildMap {
            if (refinement.match.isNotEmpty()) put("match", strings(refinement.match))
            if (refinement.with.isNotEmpty()) put("with", strings(refinement.with))
            if (refinement.cookies.isNotEmpty()) put("cookies", JsonArray(refinement.cookies.map(::JsonPrimitive)))
        }
        is FirstOf -> mapOf("firstOf" to JsonArray(lookups.map { it.toJson() }))
        is Refreshing -> base.fields() + ("refresh" to refresh.toJson())
    }

    companion object {
        val tags = listOf("environment", "jsonFile", "keychain", "setting", "browserCookies", "browserStorage", "sqlite", "firstOf")

        fun from(json: JsonElement): CredentialLookup {
            val tagged = json as? JsonObject ?: throw DefinitionError("credential is an object with one tag")
            val tag = tagged.singleTag(tags, "credential")
            val payload = tagged.getValue(tag)
            val base = decoding("credential.$tag") {
                when (tag) {
                    "environment" -> Environment(
                        (payload as? JsonPrimitive)?.takeIf { it.isString }?.content
                            ?: throw DefinitionError("credential.environment is a variable's name"),
                        loginShell = tagged.bool("loginShell") ?: false,
                    )
                    "jsonFile" -> JsonFile(JSONFileCredential.from(payload))
                    "keychain" -> Keychain(KeychainCredential.from(payload))
                    "setting" -> Setting(
                        (payload as? JsonPrimitive)?.takeIf { it.isString }?.content
                            ?: throw DefinitionError("credential.setting is a setting's name"),
                    )
                    "browserCookies" -> BrowserCookies(DefinitionJson.decodeFromJsonElement(payload))
                    "browserStorage" -> BrowserStorage(DefinitionJson.decodeFromJsonElement(payload))
                    "sqlite" -> Sqlite(DefinitionJson.decodeFromJsonElement(payload))
                    else -> FirstOf(
                        (payload as? JsonArray)?.map(::from) ?: throw DefinitionError("credential.firstOf is a list"),
                    )
                }
            }
            val refinement = Refinement(
                match = tagged.stringMap("match").orEmpty(),
                with = tagged.stringMap("with").orEmpty(),
                cookies = tagged.strings("cookies").orEmpty(),
            )
            val refined = if (refinement.isEmpty) base else Refined(base, refinement)
            val refresh = tagged["refresh"] ?: return refined
            return Refreshing(refined, CredentialRefresh.from(refresh))
        }

        private fun strings(values: Map<String, String>) = JsonObject(values.mapValues { JsonPrimitive(it.value) })
    }
}

internal object CredentialLookupSerializer : KSerializer<CredentialLookup> {
    override val descriptor: SerialDescriptor = JsonElement.serializer().descriptor
    override fun deserialize(decoder: Decoder) = CredentialLookup.from((decoder as JsonDecoder).decodeJsonElement())
    override fun serialize(encoder: Encoder, value: CredentialLookup) = (encoder as JsonEncoder).encodeJsonElement(value.toJson())
}

/**
 * `{ "domains": ["{{setting.region.site}}"], "names": ["auth"], "format": "value" }` — the first
 * browser store holding one of the names answers. `value` is the first cookie's value; `header`
 * is `name=value; …` of every one found.
 */
@Serializable
internal data class BrowserCookieCredential(
    /** Matched as suffixes; `{{setting.x}}` is filled in by the provider. */
    val domains: List<String>,
    val names: List<String>,
    val format: Format = Format.VALUE,
) {
    @Serializable
    enum class Format {
        @SerialName("value") VALUE,
        @SerialName("header") HEADER,
    }
}

/**
 * Values a browser keeps in its local storage for `origin`, each found by a key (`*` matches any
 * part) and, when its value is JSON, a path in it. `token` is required.
 */
@Serializable
internal data class BrowserStorageCredential(val origin: String, val values: Map<String, Value>) {
    init {
        if ("token" !in values) throw DefinitionError("browserStorage needs a token value")
    }

    @Serializable
    data class Value(val key: String, val path: String? = null)

    /** The site as a person reads it: `app.devin.ai`. */
    val site: String
        get() {
            val rest = origin.substringAfter("://", missingDelimiterValue = "").takeIf { it.isNotEmpty() } ?: return origin
            val authority = rest.substringBefore('/').substringBefore('?').substringBefore('#').substringAfterLast('@')
            val host = if (authority.startsWith("[")) authority.substringBefore(']') + "]" else authority.substringBefore(':')
            return host.ifEmpty { origin }
        }
}

/**
 * `{ "path": "~/…/state.vscdb", "query": "SELECT value AS token FROM …", "fields": { "token": "$.token" } }`
 * — the first row's columns, read like a JSON object. A query that would change the database is refused.
 */
@Serializable
internal data class SQLiteCredential(
    val path: PathPattern,
    val query: String,
    val fields: Map<String, String>,
    /** What to do when no key answers — the app that owns the database. */
    val hint: String? = null,
)

/**
 * `match`: a value must match its pattern, or the lookup has no key — a token is never sent to a
 * host it wasn't meant for. `with`: fixed values added to what was found, never replacing one.
 * `cookies`: named cookies read out of a Cookie-header token.
 */
internal data class Refinement(
    val match: Map<String, String> = emptyMap(),
    val with: Map<String, String> = emptyMap(),
    val cookies: List<String> = emptyList(),
) {
    val isEmpty: Boolean get() = match.isEmpty() && with.isEmpty() && cookies.isEmpty()

    /** The named cookies' values in a `name=value; …` header; one the header lacks stays unknown. */
    fun cookieValues(header: String): Map<String, String> {
        val values = mutableMapOf<String, String>()
        for (pair in header.split(';')) {
            val parts = pair.trim().split('=', limit = 2)
            if (parts.size != 2 || parts[0] !in cookies || parts[1].isEmpty()) continue
            values[parts[0]] = parts[1]
        }
        return values
    }
}

/** A Keychain item and where in its JSON password each credential value lives. */
internal data class KeychainCredential(
    val service: String,
    /** The item's account, when several logins share a service. */
    val account: String? = null,
    val encoding: Encoding? = null,
    /** Credential name → JSON path in the password. `token` is required. */
    val fields: Map<String, String>,
) {
    /** How a password is stored, when not as itself. */
    enum class Encoding(val tag: String) {
        /** go-keyring's `go-keyring-base64:<base64>` — the GitHub CLI's, for one. */
        GO_KEYRING_BASE64("goKeyringBase64"),
    }

    /** The password as stored, read as what it encodes. */
    @OptIn(kotlin.io.encoding.ExperimentalEncodingApi::class)
    fun decoded(password: String): String {
        val prefix = "go-keyring-base64:"
        if (encoding != Encoding.GO_KEYRING_BASE64 || !password.startsWith(prefix)) return password
        return runCatching { kotlin.io.encoding.Base64.Default.decode(password.removePrefix(prefix)).decodeToString(throwOnInvalidSequence = true) }
            .getOrNull() ?: password
    }

    fun toJson(): JsonElement = JsonObject(buildMap {
        put("service", JsonPrimitive(service))
        account?.let { put("account", JsonPrimitive(it)) }
        encoding?.let { put("encoding", JsonPrimitive(it.tag)) }
        fields.forEach { (name, path) -> put(name, JsonPrimitive(path)) }
    })

    companion object {
        private val reserved = setOf("service", "account", "encoding")

        fun from(json: JsonElement): KeychainCredential {
            val item = json as? JsonObject ?: throw DefinitionError("keychain is an object")
            val encoding = item["encoding"]?.let { value ->
                val tag = (value as? JsonPrimitive)?.content
                Encoding.entries.firstOrNull { it.tag == tag } ?: throw DefinitionError("keychain.encoding \"$tag\" is unknown")
            }
            return KeychainCredential(
                service = item.requireString("service", "keychain"),
                account = item.optionalString("account", "keychain"),
                encoding = encoding,
                fields = item.filterKeys { it !in reserved }.mapValues { (name, value) -> value.text("keychain.$name") },
            )
        }
    }
}

/**
 * A JSON file and where in it each credential value lives. `path` may start with `~/` or
 * `${VARIABLE:-~}/`; a `*` or a list picks the newest file.
 */
internal data class JSONFileCredential(
    val path: PathPattern,
    /** Credential name → JSON path in the file. `token` is required. */
    val fields: Map<String, String>,
    /** Further paths for a field written as a list — the first that answers. */
    val alternatives: Map<String, List<String>> = emptyMap(),
    val record: Record? = null,
    /** Values for fields the file lacks — never written back to it. */
    val defaults: Map<String, String> = emptyMap(),
) {
    /**
     * A file holding several logins — one object per key. The record that has `prefer` answers
     * before one that hasn't, then the `latest` by that value (a missing one counts as never
     * ending). Field paths are read inside the record, and a refreshed token is written back into it.
     */
    @Serializable
    data class Record(val prefer: String? = null, val latest: String? = null)

    fun toJson(): JsonElement = JsonObject(buildMap {
        put("path", path.toJson())
        record?.let { put("record", DefinitionJson.encodeToJsonElement(it)) }
        if (defaults.isNotEmpty()) put("defaults", JsonObject(defaults.mapValues { JsonPrimitive(it.value) }))
        fields.forEach { (name, first) ->
            val more = alternatives[name].orEmpty()
            put(name, if (more.isEmpty()) JsonPrimitive(first) else JsonArray((listOf(first) + more).map(::JsonPrimitive)))
        }
    })

    companion object {
        private val reserved = setOf("path", "record", "defaults")

        fun from(json: JsonElement): JSONFileCredential {
            val file = json as? JsonObject ?: throw DefinitionError("jsonFile is an object")
            val fields = mutableMapOf<String, String>()
            val alternatives = mutableMapOf<String, List<String>>()
            for ((name, value) in file) {
                if (name in reserved) continue
                if (value is JsonArray) {
                    val paths = value.map { it.text("jsonFile.$name") }
                    fields[name] = paths.firstOrNull() ?: throw DefinitionError("jsonFile.$name needs at least one path")
                    if (paths.size > 1) alternatives[name] = paths.drop(1)
                } else {
                    fields[name] = value.text("jsonFile.$name")
                }
            }
            return JSONFileCredential(
                path = PathPattern.from(file["path"] ?: throw DefinitionError("jsonFile needs \"path\"")),
                fields = fields,
                alternatives = alternatives,
                record = file["record"]?.let { DefinitionJson.decodeFromJsonElement<Record>(it) },
                defaults = file["defaults"]?.let { defaults ->
                    (defaults as? JsonObject)?.mapValues { it.value.text("jsonFile.defaults.${it.key}") }
                        ?: throw DefinitionError("jsonFile.defaults is an object")
                }.orEmpty(),
            )
        }
    }
}

/** How a refused or ageing token is renewed. */
internal sealed class CredentialRefresh {
    /** `{ "oauth2": … }` — ClaudeBar trades the refresh token and writes the new one back where it was found. */
    data class OAuth2(val refresh: OAuth2Refresh) : CredentialRefresh()

    /**
     * `{ "cli": { "cli": "gemini", "input": "/quit\n" } }` — on a 401, runs the CLI that owns the
     * credential; it renews its own file, which is then read again. ClaudeBar never writes it.
     */
    data class Cli(val call: CLICall) : CredentialRefresh()

    /** What to do when it can no longer renew the token. */
    val hint: String? get() = (this as? OAuth2)?.refresh?.hint

    fun toJson(): JsonElement = when (this) {
        is OAuth2 -> JsonObject(mapOf("oauth2" to DefinitionJson.encodeToJsonElement(refresh)))
        is Cli -> JsonObject(mapOf("cli" to DefinitionJson.encodeToJsonElement(call)))
    }

    companion object {
        fun from(json: JsonElement): CredentialRefresh {
            val refresh = json as? JsonObject ?: throw DefinitionError("credential.refresh is an object")
            refresh["cli"]?.let { return decoding("credential.refresh.cli") { Cli(DefinitionJson.decodeFromJsonElement(it)) } }
            val oauth = refresh["oauth2"] ?: throw DefinitionError("credential.refresh needs oauth2 or cli")
            return decoding("credential.refresh.oauth2") { OAuth2(DefinitionJson.decodeFromJsonElement(oauth)) }
        }
    }
}

/**
 * OAuth 2's refresh-token grant (RFC 6749 §6), with the two triggers a provider can ask for: age
 * since the last refresh, and an HTTP status.
 */
@Serializable
internal data class OAuth2Refresh(
    val tokenURL: String,
    val clientId: String,
    /** Refresh when the credential's `refreshedAt` is older than this many seconds. */
    val every: Double? = null,
    /** Refresh once, and fetch once more, when the fetch answers one of these. */
    val onStatus: List<Int> = emptyList(),
    /** Error codes in the token endpoint's answer that mean "log in again". */
    val expiredCodes: List<String> = emptyList(),
    /** What to tell the person when the session has expired. */
    val hint: String? = null,
    val bodyFormat: BodyFormat = BodyFormat.FORM,
    val scope: String? = null,
    /** Refresh when the credential's `expiresAt` is within `skew` seconds. */
    val dueWhen: Expiry? = null,
) {
    @Serializable
    enum class BodyFormat {
        /** RFC 6749's default. */
        @SerialName("form") FORM,
        @SerialName("json") JSON,
    }

    /**
     * When a token expires: the credential value holding the instant, its unit, and how early to
     * refresh. A missing value means "refresh now", unless `missingIsDue` is off — a key that never expires.
     */
    @Serializable
    data class Expiry(
        val expiresAt: String = "expiresAt",
        val unit: Unit = Unit.SECONDS,
        val skew: Double = 0.0,
        val missingIsDue: Boolean = true,
    ) {
        @Serializable
        enum class Unit {
            @SerialName("seconds") SECONDS,
            @SerialName("milliseconds") MILLISECONDS,

            /** `2026-07-26T21:03:09.138930Z`, any fraction of a second. */
            @SerialName("iso8601") ISO8601,
        }
    }
}

private fun JsonElement.text(where: String): String =
    (this as? JsonPrimitive)?.takeIf { it.isString }?.content ?: throw DefinitionError("$where is text")

private fun JsonObject.optionalString(key: String, type: String): String? = this[key]?.text("$type.$key")
