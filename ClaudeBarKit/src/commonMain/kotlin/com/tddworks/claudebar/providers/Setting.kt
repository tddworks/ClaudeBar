package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.DefinitionError
import com.tddworks.claudebar.datasources.bool
import com.tddworks.claudebar.datasources.requireString
import com.tddworks.claudebar.datasources.string
import com.tddworks.claudebar.datasources.strings
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * One thing a provider needs from the person — *API KEY*, *REGION*, *CLI DATA FOLDER*. Its
 * **kind** owns the rule a value must keep; its **scope** says whether every login shares it or
 * each login has its own (CANONICAL §1, `SettingsForm`). A definition reads it as
 * `{{setting.region}}`, and a value the chosen option carries as `{{setting.region.site}}`.
 */
@ConsistentCopyVisibility
internal data class Setting private constructor(
    val id: String,
    val label: String,
    val kind: Kind,
    val scope: Scope,
    val default: String?,
    /** The data sources that use it (`"for": ["api"]`); empty is all of them. */
    val dataSources: List<String>,
) {
    enum class Scope(val tag: String) {
        /** The same for every login — kept as `<provider>.<id>`. */
        PROVIDER("provider"),

        /** Each login has its own; *Add Account* asks for it. The default login's value is the provider-scope one. */
        ACCOUNT("account"),
    }

    /** One option of a choice, and the values it carries. */
    @ConsistentCopyVisibility
    data class Option private constructor(val id: String, val label: String, val values: Map<String, String>) {
        // An option with values is written as one object; its own keys win over a value of the same name.
        fun toJson(): JsonElement = JsonObject(values.mapValues { JsonPrimitive(it.value) } + mapOf("id" to JsonPrimitive(id), "label" to JsonPrimitive(label)))

        companion object {
            operator fun invoke(id: String, label: String? = null, values: Map<String, String> = emptyMap()) =
                Option(id, label ?: id, values)

            fun from(json: JsonElement): Option {
                if (json is JsonPrimitive && json.isString) return Option(json.content)
                val fields = (json as? JsonObject)?.mapValues { (name, value) ->
                    (value as? JsonPrimitive)?.takeIf { it.isString }?.content
                        ?: throw DefinitionError("A choice option's \"$name\" is text")
                }?.toMutableMap() ?: throw DefinitionError("A choice option is text or an object")
                val id = fields.remove("id") ?: throw DefinitionError("A choice option needs an id")
                return Option(id, fields.remove("label"), fields)
            }
        }
    }

    sealed class Kind {
        /** Free text, optionally matching a pattern. */
        data class Text(val pattern: String? = null) : Kind()

        /** A key — kept in the vault, never in settings, never a default. */
        data object Secret : Kind()

        /** One of its options. */
        data class Choice(val options: List<Option>) : Kind()

        /** A path on this Mac, `~` allowed; optionally one that must exist. */
        data class Path(val mustExist: Boolean = false) : Kind()

        fun toJson(): JsonElement = when (this) {
            is Text -> if (pattern == null) JsonPrimitive("text")
            else JsonObject(mapOf("text" to JsonObject(mapOf("pattern" to JsonPrimitive(pattern)))))
            Secret -> JsonPrimitive("secret")
            is Choice -> JsonObject(mapOf("choice" to JsonArray(options.map { it.toJson() })))
            is Path -> JsonObject(mapOf("path" to JsonObject(mapOf("mustExist" to JsonPrimitive(mustExist)))))
        }

        companion object {
            fun from(json: JsonElement): Kind {
                if (json is JsonPrimitive && json.isString) return when (json.content) {
                    "text" -> Text()
                    "secret" -> Secret
                    "path" -> Path()
                    else -> throw DefinitionError("Unknown setting kind '${json.content}'")
                }
                val o = json as? JsonObject ?: throw DefinitionError("A setting kind is a name or an object")
                val choice = o["choice"]?.takeUnless { it is JsonNull }
                if (choice != null) {
                    return Choice((choice as? JsonArray ?: throw DefinitionError("choice is a list")).map(Option::from))
                }
                if (o.containsKey("path")) {
                    return Path((o["path"] as? JsonObject ?: throw DefinitionError("path is an object")).bool("mustExist") ?: false)
                }
                val text = o["text"] as? JsonObject ?: throw DefinitionError("A setting kind needs \"text\", \"choice\" or \"path\"")
                return Text(text.string("pattern"))
            }
        }
    }

    /** Whether the data source [kind] uses it. */
    fun isUsed(kind: String): Boolean = dataSources.isEmpty() || kind in dataSources

    private val isSecret: Boolean get() = kind == Kind.Secret

    private val options: List<Option> get() = (kind as? Kind.Choice)?.options ?: emptyList()

    /** The value a form holds for what was typed: the typed text, trimmed; a blank is the default, or a choice's first option. */
    fun value(typed: String?): String {
        val text = (typed ?: "").trim()
        if (text.isNotEmpty()) return text
        return default ?: options.firstOrNull()?.id ?: ""
    }

    /** The folder a login's values name for this setting — only a path setting names one. */
    fun path(values: Map<String, String>): String? = if (kind is Kind.Path) values[id] else null

    /** Whether two logins' values are the same place — only a path can be; two spellings of one folder are. */
    fun isSamePlace(value: String, other: String, paths: PathChecking): Boolean =
        kind is Kind.Path && paths.canonical(value) == paths.canonical(other)

    /** What *Add Account* prints when [value] breaks this setting's rule, or null when it keeps it. An empty value is never kept. */
    fun check(value: String, paths: PathChecking): String? {
        if (value.isEmpty()) return "Fill in $label."
        return when (val kind = kind) {
            Kind.Secret -> null
            is Kind.Text -> kind.pattern?.let { if (Regex(it).containsMatchIn(value)) null else "Enter a valid $label." }
            is Kind.Choice -> if (kind.options.any { it.id == value }) null else "Choose a $label from the list."
            is Kind.Path -> {
                val expanded = paths.expanded(value)
                when {
                    !expanded.startsWith("/") && !expanded.startsWith("~") -> "Enter a full path for $label."
                    kind.mustExist && !paths.isFolder(expanded) -> "Choose an existing folder for $label."
                    else -> null
                }
            }
        }
    }

    /**
     * What [value] fills in a definition: `{{setting.<id>}}`, and for a choice
     * `{{setting.<id>.<name>}}` for each value its option carries — keyed by the name after
     * `setting.`. Empty for a secret: a key reaches a fetch only through its credential lookup.
     */
    fun fills(typed: String?): Map<String, String> {
        val chosen = value(typed)
        if (isSecret || chosen.isEmpty()) return emptyMap()
        val fills = mutableMapOf(id to chosen)
        options.firstOrNull { it.id == chosen }?.values?.forEach { (name, text) -> fills["$id.$name"] = text }
        return fills
    }

    /** [text] once for every value this setting can fill into it — each option's, or the default's — so *Import* lists every host a key may go to. */
    fun expanding(text: String): List<String> {
        if (!text.contains("{{setting.$id")) return listOf(text)
        val possible = (kind as? Kind.Choice)?.options?.map { fills(it.id) } ?: listOf(fills(null))
        return possible.map { fills -> fills.entries.fold(text) { result, (key, value) -> result.replace("{{setting.$key}}", value) } }
    }

    /** A login's own value among its saved values — only an account-scope setting has one. */
    fun ownValue(values: Map<String, String>): String? = if (scope == Scope.ACCOUNT) values[id] else null

    /** Puts [value] where this setting keeps it: a secret with the keys for the vault, anything else with the saved values. */
    fun keep(value: String, entry: SettingEntry, paths: PathChecking) {
        val kept = if (kind is Kind.Path) paths.canonical(value) else value
        if (isSecret) entry.secrets[id] = kept else entry.values[id] = kept
    }

    /** The same setting, asked for by *Add Account*. */
    val inAccountScope: Setting get() = Setting(id, label, kind, Scope.ACCOUNT, default)

    fun toJson(): JsonObject = JsonObject(buildMap {
        put("id", JsonPrimitive(id))
        put("label", JsonPrimitive(label))
        put("kind", kind.toJson())
        put("scope", JsonPrimitive(scope.tag))
        default?.let { put("default", JsonPrimitive(it)) }
        if (dataSources.isNotEmpty()) put("for", JsonArray(dataSources.map(::JsonPrimitive)))
    })

    companion object {
        /** A secret never has a default. */
        operator fun invoke(
            id: String,
            label: String,
            kind: Kind = Kind.Text(),
            scope: Scope = Scope.PROVIDER,
            default: String? = null,
            dataSources: List<String> = emptyList(),
        ) = Setting(id, label, kind, scope, if (kind == Kind.Secret) null else default, dataSources)

        fun from(json: JsonElement): Setting {
            val o = json as? JsonObject ?: throw DefinitionError("a setting is an object")
            val id = o.requireString("id", "setting")
            val declared = o["kind"]?.takeUnless { it is JsonNull }
            val kind = when {
                declared != null -> Kind.from(declared)
                // The form before kinds: `"secret": true`, `"choices": […]`.
                o.bool("secret") == true -> Kind.Secret
                o["choices"] is JsonArray -> Kind.Choice(o.strings("choices")!!.map { Option(it) })
                else -> Kind.Text()
            }
            val value = o.string("default")
            if (kind == Kind.Secret && value != null) throw DefinitionError("Setting '$id' is a secret, so it has no default")
            val scope = o.string("scope")?.let { tag -> Scope.entries.firstOrNull { it.tag == tag } ?: throw DefinitionError("Setting '$id' has an unknown scope '$tag'") }
            return Setting(
                id = id,
                label = o.requireString("label", "setting '$id'"),
                kind = kind,
                scope = scope ?: Scope.PROVIDER,
                default = value,
                dataSources = o.strings("for") ?: emptyList(),
            )
        }
    }
}

/** What a filled form keeps: saved values, and keys for the vault. */
internal data class SettingEntry(
    val values: MutableMap<String, String> = mutableMapOf(),
    val secrets: MutableMap<String, String> = mutableMapOf(),
)

/** What a path setting asks of this Mac — the port its rule reads through. */
internal interface PathChecking {
    /** Home and environment defaults expanded, without making relative paths absolute. */
    fun expanded(path: String): String

    /** Whether [path] (`~` allowed) is an existing folder. */
    fun isFolder(path: String): Boolean

    /** The same place written one way, symlinks resolved, so two spellings of one folder compare equal. */
    fun canonical(path: String): String
}
