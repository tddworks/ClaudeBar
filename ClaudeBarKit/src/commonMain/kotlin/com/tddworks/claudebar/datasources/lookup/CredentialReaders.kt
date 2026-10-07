package com.tddworks.claudebar.datasources.lookup

import com.tddworks.claudebar.datasources.Credential
import com.tddworks.claudebar.datasources.CredentialFinding
import com.tddworks.claudebar.datasources.FoundCredential
import com.tddworks.claudebar.datasources.JsonPath
import com.tddworks.claudebar.datasources.JsonScope
import com.tddworks.claudebar.datasources.Jwt
import com.tddworks.claudebar.datasources.Paths
import com.tddworks.claudebar.datasources.SecretStore
import com.tddworks.claudebar.diagnostics.AppLog
import kotlinx.io.buffered
import kotlinx.io.files.Path
import kotlinx.io.files.SystemFileSystem
import kotlinx.io.readString
import kotlinx.io.writeString
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlin.random.Random

/** `environment` — an environment variable holds the token. */
internal class EnvironmentReader(
    val name: String,
    private val environment: (String) -> String?,
    /** The person's login shell, asked only when the app's own environment lacks the variable. */
    private val loginShell: ((String) -> String?)? = null,
) : CredentialFinding {
    override fun find(): FoundCredential? {
        val value = environment(name)?.let(::trimmed)?.ifEmpty { null } ?: loginShell?.invoke(name)?.let(::trimmed)
        if (value.isNullOrEmpty()) return null
        return FoundCredential(Credential(mapOf("token" to value)))
    }
}

/**
 * `jsonFile` — a JSON file holds the token and its companions. A refreshed token is written back
 * into the same file, every other field kept and every value keeping its JSON type, because the
 * CLI that owns the file must keep working.
 */
internal class JSONFileReader(
    val file: JSONFileCredential,
    private val home: String,
    private val environment: (String) -> String?,
) : CredentialFinding {
    val path: String get() = Paths.resolve(file.path, home, environment)

    override fun find(): FoundCredential? {
        val document = readDocument() ?: return null
        file.record?.let { return chosen(it, document) }
        val values = valuesWithAlternatives(document)
        if (values["token"] == null) return null
        return FoundCredential(Credential(file.defaults + values)) { write(it) }
    }

    /** The fields without requiring a token — what a context file supplies. */
    fun fields(): Map<String, String> = readDocument()?.let { CredentialDocument.values(file.fields, it) }.orEmpty()

    fun write(credential: Credential) {
        val document = readDocument() ?: return
        // A default the file lacked is never written into it.
        val own = credential.values.filter { file.defaults[it.key] == null || it.value != file.defaults[it.key] }
        save(CredentialDocument.updated(document, Credential(own), file.fields))
    }

    /** The fields, each from the first of its paths that answers. */
    private fun valuesWithAlternatives(document: JsonObject): Map<String, String> {
        val values = CredentialDocument.values(file.fields, document).toMutableMap()
        for ((name, paths) in file.alternatives) {
            if (values[name] != null) continue
            paths.firstNotNullOfOrNull { CredentialDocument.values(mapOf(name to it), document)[name] }?.let { values[name] = it }
        }
        return values
    }

    /** The record the rule picks, filled out with the defaults; a refreshed token goes back into that record only. */
    private fun chosen(rule: JSONFileCredential.Record, document: JsonObject): FoundCredential? {
        val candidates = document.mapNotNull { (key, value) ->
            val record = value as? JsonObject ?: return@mapNotNull null
            val values = CredentialDocument.values(file.fields, record)
            if (values["token"] == null) null else key to values
        }
        fun preferred(values: Map<String, String>) = rule.prefer?.let { if (values[it] != null) 1 else 0 } ?: 0
        fun latest(values: Map<String, String>) =
            rule.latest?.let { values[it] }?.let(::instant) ?: Double.POSITIVE_INFINITY
        val best = candidates.maxWithOrNull(compareBy<Pair<String, Map<String, String>>>({ preferred(it.second) }, { latest(it.second) }))
            ?: return null
        val (key, values) = best
        return FoundCredential(Credential(file.defaults + values)) { renewed ->
            write(renewed.values.filter { it.key in values || it.key !in file.defaults }, key)
        }
    }

    private fun write(values: Map<String, String>, key: String) {
        val document = readDocument() ?: return
        val record = document[key] as? JsonObject ?: return
        save(JsonObject(document + (key to CredentialDocument.updated(record, Credential(values), file.fields))))
    }

    private fun save(updated: JsonObject) {
        try {
            writeAtomically(path, prettyJson.encodeToString(JsonElement.serializer(), sortedKeys(updated)))
            AppLog.credentials.info("Saved refreshed credentials to ${file.path}")
        } catch (error: Exception) {
            AppLog.credentials.error("Failed to save refreshed credentials to ${file.path}: ${error.message}")
        }
    }

    private fun readDocument(): JsonObject? = readText(path)?.let { runCatching { Json.parseToJsonElement(it) }.getOrNull() } as? JsonObject

    companion object {
        /** An instant written as seconds, or as ISO 8601 with any fraction. */
        fun instant(text: String): Double? = text.toDoubleOrNull() ?: ISO8601Instant.parse(text)

        @OptIn(ExperimentalSerializationApi::class)
        private val prettyJson = Json { prettyPrint = true; prettyPrintIndent = "  " }
    }
}

/**
 * `keychain` — a generic-password item read and written with macOS's `security` tool, never
 * `SecItemCopyMatching`: the item belongs to another app's signature, and the Apple-signed tool
 * doesn't prompt (#94). A refreshed token is written back as compact JSON: a pretty-printed
 * password comes back hex-encoded from `security -w` (#255).
 */
internal class KeychainReader(
    val item: KeychainCredential,
    private val security: SecurityTool,
    private val userName: String = loginUserName(),
) : CredentialFinding {
    override fun find(): FoundCredential? {
        val account = item.account?.let { listOf("-a", it) }.orEmpty()
        val result = security.run(listOf("find-generic-password", "-s", item.service) + account + "-w")
        if (result.status != 0) {
            AppLog.credentials.error("Keychain read of '${item.service}' failed: security exited ${result.status}")
            return null
        }
        val password = item.decoded(trimmed(result.output))
        if (password.isEmpty()) return null
        val document = jsonObject(password)
        val values = when {
            document != null -> CredentialDocument.values(item.fields, document)
            item.fields["token"] == "$" -> mapOf("token" to password)
            else -> {
                // Shape only — never the payload, which is the token itself.
                AppLog.credentials.error("Keychain item '${item.service}' did not hold the expected JSON")
                return null
            }
        }
        if (values["token"] == null) return null
        return FoundCredential(Credential(values)) { write(it, password) }
    }

    fun write(credential: Credential, over: String) {
        // An encoded item belongs to another tool's library; never rewritten.
        if (item.encoding != null) return
        val document = jsonObject(over) ?: return
        val payload = Json.encodeToString(JsonElement.serializer(), CredentialDocument.updated(document, credential, item.fields))
        val result = security.run(listOf("add-generic-password", "-U", "-s", item.service, "-a", userName, "-w", payload))
        if (result.status == 0) {
            AppLog.credentials.info("Saved refreshed credentials to Keychain item '${item.service}'")
        } else {
            AppLog.credentials.error("Failed to save credentials to Keychain item '${item.service}' (exit ${result.status})")
        }
    }

    private fun jsonObject(password: String): JsonObject? =
        decode(password)?.let { runCatching { Json.parseToJsonElement(it.decodeToString()) }.getOrNull() } as? JsonObject

    companion object {
        /**
         * `security -w` hex-encodes a password with bytes outside printable ASCII on macOS 26.
         * JSON never starts with a hex digit, so all-hex is the encoded form.
         */
        fun decode(password: String): ByteArray? {
            if (password.isNotEmpty() && password.length % 2 == 0) {
                if (password.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }) {
                    return ByteArray(password.length / 2) { password.substring(it * 2, it * 2 + 2).toInt(16).toByte() }
                }
            }
            return password.encodeToByteArray()
        }
    }
}

/** What `/usr/bin/security` answered: its exit status and what it printed. */
internal data class SecurityResult(val status: Int, val output: String)

/** macOS's `security` tool, run with these arguments. */
internal fun interface SecurityTool {
    fun run(arguments: List<String>): SecurityResult
}

/** The name of the person signed in to this Mac — the account a Keychain item is saved under. */
internal expect fun loginUserName(): String

/** `firstOf` — the lookup order: the first reader that answers wins. */
internal class FirstOfReader(val readers: List<CredentialFinding>) : CredentialFinding {
    override fun find(): FoundCredential? = readers.firstNotNullOfOrNull { it.find() }
}

/** Reading credential values out of a JSON document, and writing refreshed ones back without changing a value's JSON type. */
internal object CredentialDocument {
    /** `"$.tokens.id_token#jwt.email"` reads a claim out of a JWT's payload — display metadata only. */
    fun values(fields: Map<String, String>, document: JsonObject): Map<String, String> {
        val scope = JsonScope(document)
        val values = mutableMapOf<String, String>()
        for ((name, field) in fields) {
            val parts = field.split("#jwt.")
            var value = scope.string(parts[0])
            if (parts.size == 2) value = value?.let { Jwt.claim(parts[1], it) }
            value?.let(::trimmed)?.takeIf { it.isNotEmpty() }?.let { values[name] = it }
        }
        return values
    }

    fun updated(document: JsonObject, credential: Credential, fields: Map<String, String>): JsonObject {
        var updated = document
        val scope = JsonScope(document)
        for ((name, path) in fields) {
            if (path == "$" || "#jwt." in path) continue
            val value = credential[name] ?: continue
            val existing = scope.value(path)
            // A number stays a number: Claude Code reads `expiresAt` as one.
            val isNumber = existing is JsonPrimitive && !existing.isString && existing !is kotlinx.serialization.json.JsonNull
            val number = value.toDoubleOrNull()?.takeIf { it.isFinite() }
            updated = if ((isNumber || (existing == null && name == "expiresAt")) && number != null) {
                JsonPath.set(numberJson(number), path, updated)
            } else {
                JsonPath.set(JsonPrimitive(value), path, updated)
            }
        }
        return updated
    }

    private fun numberJson(number: Double): JsonPrimitive =
        if (number == kotlin.math.floor(number) && kotlin.math.abs(number) < 9.0e15) JsonPrimitive(number.toLong()) else JsonPrimitive(number)
}

/** `setting` — a key the person gave ClaudeBar, read from its vault. */
internal class SettingReader(
    val name: String,
    private val providerId: String,
    private val secrets: SecretStore?,
) : CredentialFinding {
    override fun find(): FoundCredential? {
        val value = secrets?.secret(name, providerId)?.let(::trimmed)
        if (value.isNullOrEmpty()) return null
        return FoundCredential(Credential(mapOf("token" to value)))
    }
}

/**
 * A lookup refined: the named cookies read out of a Cookie-header token and the `with` values
 * added where nothing was found, then no key unless each `match` pattern matches its value.
 */
internal class RefinedReader(val base: CredentialFinding, val refinement: Refinement) : CredentialFinding {
    override fun find(): FoundCredential? {
        val found = base.find() ?: return null
        var credential = found.credential
        credential["token"]?.let { header ->
            for ((name, value) in refinement.cookieValues(header)) if (credential[name] == null) credential = credential.with(name, value)
        }
        for ((name, value) in refinement.with) if (credential[name] == null) credential = credential.with(name, value)
        // Checked after `with`, so a value a setting added must fit too.
        for ((name, pattern) in refinement.match) {
            val value = credential[name]
            if (value == null || !Regex(pattern).containsMatchIn(value)) {
                AppLog.credentials.info("A key was found but its $name isn't one this provider uses; not using it")
                return null
            }
        }
        return found.copy(credential = credential)
    }
}

/** The file's text, or null when it can't be read. */
internal fun readText(path: String): String? = runCatching {
    SystemFileSystem.source(Path(path)).buffered().use { it.readString() }
}.getOrNull()

/** Writes beside the file, then moves over it, so a reader never sees half a file. */
internal fun writeAtomically(path: String, text: String) {
    val temporary = Path("$path.claudebar-${Random.nextLong().toULong()}")
    SystemFileSystem.sink(temporary).buffered().use { it.writeString(text) }
    SystemFileSystem.atomicMove(temporary, Path(path))
}

/** The same JSON with every object's keys in order — a stable file a person can diff. */
internal fun sortedKeys(json: JsonElement): JsonElement = when (json) {
    is JsonObject -> JsonObject(json.entries.sortedBy { it.key }.associate { it.key to sortedKeys(it.value) })
    is JsonArray -> JsonArray(json.map(::sortedKeys))
    else -> json
}
