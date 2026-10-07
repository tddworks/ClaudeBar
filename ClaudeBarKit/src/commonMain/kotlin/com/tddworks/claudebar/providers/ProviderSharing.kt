package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.Fetch
import com.tddworks.claudebar.datasources.lookup.CredentialLookup
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * *Export…* — the definition as a file to share. A key is only ever a NAME in a definition
 * (`"setting": "apiKey"`); its value lives in the vault, so no exported file holds one
 * (USER_JOURNEYS F9). The origin is left out: whoever imports it decides.
 */
internal fun ProviderDefinition.exported(): String = prettyJson(toJson(), "")

/** *Key needed* — the settings this definition asks whoever adds it for. */
internal val ProviderDefinition.neededSettings: List<String>
    get() = dataSources.flatMap { source -> source.credential?.let(::keyNames) ?: emptyList() }.toSet().sorted()

/**
 * Where it sends a key — the host of every URL a data source with a credential may call, with
 * each setting's every option spelled out, so a region a person might pick later is listed too.
 */
internal val ProviderDefinition.keyDestinations: List<String>
    get() = dataSources.filter { it.credential != null }.flatMap { it.fetch.urls }
        .flatMap { url -> settings.fold(listOf(url)) { texts, setting -> texts.flatMap(setting::expanding) } }
        .map { host(it) ?: it }.toSet().sorted()

/** Every command it runs, as typed. */
internal val ProviderDefinition.commands: List<String>
    get() = dataSources.flatMap { it.fetch.commands }.map { it.joinToString(" ") }.distinct()

/** What a shared file would do, shown BEFORE anything is saved or run (USER_JOURNEYS F10). */
internal data class ImportReview(
    /** As it will be saved: origin custom, its id kept unless taken. */
    val definition: ProviderDefinition,
    /** "It will send your key to that address." */
    val sendsKeyTo: List<String>,
    /** The commands it runs — a person agrees to them first. */
    val runs: List<String>,
    /** "Key needed". */
    val needs: List<String>,
)

/** The same definition under another id, as custom; rebuilt as Swift does, without `cliPlaces`, `order` or `guestPasses`. */
internal fun ProviderDefinition.renamed(id: String): ProviderDefinition = ProviderDefinition(
    profile = ProviderProfile(id, profile.name, profile.links, profile.look, ProviderProfile.Origin.CUSTOM),
    cli = cli,
    enabledByDefault = enabledByDefault,
    dataSources = dataSources,
    defaultDataSource = defaultDataSource,
    together = together,
    accounts = accounts,
    settings = settings,
    usageHistory = usageHistory,
    setup = setup,
)

private fun keyNames(lookup: CredentialLookup): List<String> = when (lookup) {
    is CredentialLookup.Setting -> listOf(lookup.name)
    is CredentialLookup.FirstOf -> lookup.lookups.flatMap(::keyNames)
    is CredentialLookup.Refreshing -> keyNames(lookup.base)
    is CredentialLookup.Refined -> keyNames(lookup.base)
    else -> emptyList()
}

/** Every URL a request may go to, as written — `{{setting.x}}` and `{{token}}` left for the caller. */
private val Fetch.urls: List<String>
    get() = when (this) {
        is Fetch.Http -> listOf(request.url)
        is Fetch.HttpSteps -> steps.steps.map { it.request.url }
        // Only this Mac's loopback address, on whatever port the app listens.
        is Fetch.LocalServer -> call.paths.map { "https://127.0.0.1:{{port}}$it" }
        else -> emptyList()
    }

/** Every command it may run, as argv. */
private val Fetch.commands: List<List<String>>
    get() = when (this) {
        is Fetch.JsonRpc -> listOf(listOf(call.cli) + call.args)
        is Fetch.Cli -> listOf(listOf(call.cli) + call.args)
        is Fetch.Command -> listOf(listOf(call.cli) + call.args)
        is Fetch.LocalServer -> listOf(
            listOf("/usr/bin/pgrep", "-lf", call.process.names.joinToString("|")),
            listOf("/usr/sbin/lsof", "-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p", "{{pid}}"),
        )
        // The person's own script — *Import* shows it before anything runs.
        is Fetch.Script -> listOf(listOf("/bin/sh", "-c", call.run))
        else -> emptyList()
    }

private val urlPattern = Regex("""^[A-Za-z][A-Za-z0-9+.-]*://([^/?#]*)""")

/** A URL's host, as `URL(string:)?.host` reads it; null when the text isn't such a URL. */
private fun host(text: String): String? {
    if (text.any { it == '{' || it == '}' || it == ' ' }) return null
    val authority = urlPattern.find(text)?.groupValues?.get(1) ?: return null
    val hostAndPort = authority.substringAfterLast('@')
    val host = if (hostAndPort.startsWith("[")) hostAndPort.substringBefore(']').removePrefix("[")
    else hostAndPort.substringBefore(':')
    return host.ifEmpty { null }
}

/** Two-space indents, `"name" : value` and sorted names — the layout Swift's pretty, sorted encoder writes. */
internal fun prettyJson(element: JsonElement, indent: String): String {
    val inner = "$indent  "
    return when (element) {
        is JsonObject -> if (element.isEmpty()) "{}" else element.entries.sortedBy { it.key }
            .joinToString(",\n", "{\n", "\n$indent}") { (name, value) -> "$inner${JsonPrimitive(name)} : ${prettyJson(value, inner)}" }
        is JsonArray -> if (element.isEmpty()) "[]" else element
            .joinToString(",\n", "[\n", "\n$indent]") { "$inner${prettyJson(it, inner)}" }
        else -> element.toString()
    }
}
