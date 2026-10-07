package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.CommandCall
import com.tddworks.claudebar.datasources.DataSourceDefinition
import com.tddworks.claudebar.datasources.Fetch
import com.tddworks.claudebar.datasources.FileCall
import com.tddworks.claudebar.datasources.HTTPRequest
import com.tddworks.claudebar.datasources.PathPattern
import com.tddworks.claudebar.datasources.WorkingDirectory
import com.tddworks.claudebar.datasources.lookup.CredentialLookup
import com.tddworks.claudebar.datasources.mapping.Amount
import com.tddworks.claudebar.datasources.mapping.JSONMapping
import com.tddworks.claudebar.datasources.mapping.Mapping
import com.tddworks.claudebar.datasources.mapping.NameRule
import com.tddworks.claudebar.datasources.mapping.QuotaKind
import com.tddworks.claudebar.datasources.mapping.QuotaRule
import com.tddworks.claudebar.datasources.mapping.ResetRef
import com.tddworks.claudebar.datasources.mapping.TextMapping
import com.tddworks.claudebar.datasources.mapping.ValueRef
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement

/**
 * *Add Provider*'s answers, step by step — *Start from*, *Connect*, *Map fields*, *Look* —
 * turned into a `ProviderDefinition`: the same data a built-in is, run by the same `Provider`.
 * Pure: no I/O, so every step is tested on its own.
 */
internal class ProviderDraft(val start: Start) {
    /** *Start from: API · CLI · File · Copy a provider* — a closed list in the words Settings prints (USER_JOURNEYS F4). */
    sealed class Start {
        data object Api : Start()
        data object Cli : Start()
        data object File : Start()
        data class Copy(val source: ProviderDefinition) : Start()
    }

    /** *Key lookup order* for an API. */
    sealed class KeySource {
        /** *API key* — pasted here, kept in ClaudeBar's vault. */
        data object ApiKey : KeySource()

        /** *Environment variable* — named here, read from the environment. */
        data class Environment(val variable: String) : KeySource()
    }

    /** *Sent as*. */
    sealed class SentAs {
        /** `Authorization: Bearer <key>`. */
        data object Bearer : SentAs()

        /** `<header>: <key>`. */
        data class Header(val name: String) : SentAs()
    }

    /** *Map fields*: what the numbers mean — *Used · Remaining · Limit*. */
    sealed class Measure {
        data object PercentUsed : Measure()
        data object PercentLeft : Measure()

        /** Money remaining, of a limit or — without one — a balance. */
        data class Money(val currency: String) : Measure()
    }

    enum class ResetsFormat { ISO8601, EPOCH_SECONDS, SECONDS_FROM_NOW }

    /** What a draft still needs before it can be saved. */
    sealed class Missing(message: String) : Exception(message) {
        data object Name : Missing("Give it a name.")
        data object Url : Missing("Enter the URL to ask.")
        data object Command : Missing("Enter the command to run.")
        data object Path : Missing("Choose the file to read.")
        data object Used : Missing("Pick the value that says how much is used.")
        data object Remaining : Missing("Pick the value that says how much is left.")
        data object TextLabel : Missing("Name the line that holds the number.")
    }

    // Connect
    var url = ""
    var command = ""
    var path = ""
    var key: KeySource? = KeySource.ApiKey
    var sentAs: SentAs = SentAs.Bearer

    // Map fields
    var measure: Measure = Measure.PercentUsed
    var used: String? = null
    var remaining: String? = null
    var limit: String? = null
    var resets: String? = null
    var resetsFormat = ResetsFormat.ISO8601

    /** For a CLI that prints text: the line that names the percentage. */
    var textLabel: String? = null
    var quotaName = "Usage"

    // Look
    var name = if (start is Start.Copy) start.source.profile.name else ""
    var symbol: String? = null
    var color: ProviderLook.Shades? = null
    var dashboard = ""

    /** The definition this draft describes, under [id] — minted once by the catalog, never derived from the name alone. Throws what is missing. */
    fun definition(id: String): ProviderDefinition {
        val name = name.trim()
        if (name.isEmpty()) throw Missing.Name

        if (start is Start.Copy) {
            val source = start.source
            return ProviderDefinition(
                profile = profile(id, name, source.profile.links, source.profile.look),
                cli = source.cli,
                dataSources = source.dataSources,
                defaultDataSource = source.defaultDataSource,
                accounts = source.accounts,
                settings = source.settings,
            )
        }

        val source = DataSourceDefinition(
            kind = kind, label = label, summary = summary,
            credential = credential(), fetch = fetch(), mapping = mapping(),
        )
        return ProviderDefinition(
            profile = profile(id, name, links, null),
            cli = cliName,
            dataSources = listOf(source),
            defaultDataSource = kind,
            accounts = accounts(),
        )
    }

    /** *Connect → Test Connection*: the key lookup and the fetch, nothing mapped yet — so a person sees what comes back before mapping it (F5). */
    fun connection(): DataSourceDefinition {
        if (start is Start.Copy) return start.source.dataSource(start.source.defaultDataSource) ?: start.source.dataSources[0]
        return DataSourceDefinition(kind = kind, label = label, credential = credential(), fetch = fetch(), mapping = Mapping.Json(JSONMapping(quotas = emptyList())))
    }

    private val kind: String
        get() = when (start) {
            Start.Api -> "api"
            Start.Cli -> "cli"
            Start.File -> "file"
            is Start.Copy -> start.source.defaultDataSource
        }

    private val label: String
        get() = when (start) {
            Start.Api -> "API"
            Start.Cli -> "CLI"
            Start.File -> "File"
            is Start.Copy -> kind
        }

    private val summary: String
        get() = when (start) {
            Start.Api -> "Calls $url"
            Start.Cli -> "Runs `$command`"
            Start.File -> "Reads $path"
            is Start.Copy -> ""
        }

    private val cliName: String? get() = if (start == Start.Cli) words(command).firstOrNull() else null

    private val links: ProviderDefinition.Links
        get() = ProviderDefinition.Links(dashboardTemplate = dashboard.trim().ifEmpty { null })

    private fun profile(id: String, name: String, links: ProviderDefinition.Links, base: ProviderLook?) = ProviderProfile(
        id = id,
        name = name,
        links = links,
        look = ProviderLook(symbol = symbol ?: base?.symbol, icon = base?.icon, color = color ?: base?.color, gradientEnd = base?.gradientEnd),
        origin = ProviderProfile.Origin.CUSTOM,
    )

    /**
     * A key that is the person's own takes a second account by a second key, typed into *Add
     * Account* and kept under that account. A key read from an environment variable is the
     * default login's alone.
     */
    private fun accounts(): ProviderDefinition.Accounts? {
        val credential = credential() ?: return null
        val patch = mutableMapOf<String, JsonElement>()
        if (credential != CredentialLookup.Setting("apiKey")) {
            patch[kind] = Json.parseToJsonElement("""{ "credential": { "environment": null, "setting": "apiKey" } }""")
        }
        return ProviderDefinition.Accounts(form = listOf(Setting("apiKey", "API key", Setting.Kind.Secret, Setting.Scope.ACCOUNT)), patch = patch)
    }

    private fun credential(): CredentialLookup? {
        if (start != Start.Api) return null
        return when (val key = key ?: return null) {
            KeySource.ApiKey -> CredentialLookup.Setting("apiKey")
            is KeySource.Environment -> CredentialLookup.Environment(key.variable)
        }
    }

    private fun fetch(): Fetch = when (start) {
        Start.Api -> {
            val url = url.trim()
            if (url.isEmpty()) throw Missing.Url
            val headers = mutableMapOf("Accept" to "application/json")
            if (key != null) {
                when (val sentAs = sentAs) {
                    SentAs.Bearer -> headers["Authorization"] = "Bearer {{token}}"
                    is SentAs.Header -> headers[sentAs.name] = "{{token}}"
                }
            }
            Fetch.Http(HTTPRequest(url = url, headers = headers))
        }
        Start.Cli -> {
            val words = words(command)
            val cli = words.firstOrNull() ?: throw Missing.Command
            // A command a person types runs over pipes; a TUI needs a definition's `cli`.
            Fetch.Command(CommandCall(cli = cli, args = words.drop(1), workingDirectory = WorkingDirectory.DEDICATED))
        }
        Start.File -> {
            val path = path.trim()
            if (path.isEmpty()) throw Missing.Path
            Fetch.File(FileCall(PathPattern(path)))
        }
        is Start.Copy -> error("A copy keeps its data sources")
    }

    private fun mapping(): Mapping {
        val textLabel = textLabel
        if (start == Start.Cli && textLabel != null) {
            if (textLabel.isEmpty()) throw Missing.TextLabel
            val number = """([0-9]+(?:\.[0-9]+)?)\s*%"""
            val pattern = if (measure == Measure.PercentUsed) TextMapping.QuotaPattern(QuotaKind.TIME, quotaName, textLabel, usedPercent = number)
            else TextMapping.QuotaPattern(QuotaKind.TIME, quotaName, textLabel, leftPercent = number)
            return Mapping.Text(TextMapping(quotas = listOf(pattern), whenEmpty = "Could not find $textLabel"))
        }

        val resetsAt: List<ResetRef> = resets?.let { path ->
            listOf(
                when (resetsFormat) {
                    ResetsFormat.ISO8601 -> ResetRef.Iso8601(path)
                    ResetsFormat.EPOCH_SECONDS -> ResetRef.EpochSeconds(path)
                    ResetsFormat.SECONDS_FROM_NOW -> ResetRef.SecondsFromNow(path)
                },
            )
        } ?: emptyList()
        val name = NameRule(text = quotaName)

        val rule = when (val measure = measure) {
            Measure.PercentUsed -> QuotaRule(
                kind = QuotaKind.TIME, name = name, resetsAt = resetsAt,
                usedPercent = listOf(ValueRef.Path(used ?: throw Missing.Used)),
            )
            Measure.PercentLeft -> QuotaRule(
                kind = QuotaKind.TIME, name = name, resetsAt = resetsAt,
                leftPercent = listOf(ValueRef.Path(remaining ?: throw Missing.Remaining)),
            )
            is Measure.Money -> QuotaRule(
                kind = QuotaKind.TIME, name = name, resetsAt = resetsAt,
                left = QuotaRule.MoneyLeft(
                    money = Amount.Value(listOf(ValueRef.Path(remaining ?: throw Missing.Remaining))),
                    of = limit?.let { Amount.Value(listOf(ValueRef.Path(it))) },
                    currency = measure.currency,
                ),
            )
        }
        return Mapping.Json(JSONMapping(quotas = listOf(rule)))
    }

    companion object {
        /** A command line split into words, honouring "double" and 'single' quotes. */
        fun words(line: String): List<String> {
            val words = mutableListOf<String>()
            val current = StringBuilder()
            var quote: Char? = null
            var inWord = false
            for (character in line) {
                val open = quote
                if (open != null) {
                    if (character == open) quote = null else current.append(character)
                } else if (character == '"' || character == '\'') {
                    quote = character
                    inWord = true
                } else if (character.isWhitespace()) {
                    if (inWord) {
                        words += current.toString()
                        current.clear()
                        inWord = false
                    }
                } else {
                    current.append(character)
                    inWord = true
                }
            }
            if (inWord) words += current.toString()
            return words
        }
    }
}
