package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.DataSourceDefinition
import com.tddworks.claudebar.datasources.DefinitionError
import com.tddworks.claudebar.datasources.Fetch
import com.tddworks.claudebar.datasources.HTTPRequest
import com.tddworks.claudebar.datasources.ScriptCall
import com.tddworks.claudebar.datasources.double
import com.tddworks.claudebar.datasources.mapping.Mapping
import com.tddworks.claudebar.datasources.mapping.TextMapping
import com.tddworks.claudebar.datasources.requireString
import com.tddworks.claudebar.datasources.strings
import com.tddworks.claudebar.diagnostics.AppLog
import kotlinx.io.buffered
import kotlinx.io.files.Path
import kotlinx.io.files.SystemFileSystem
import kotlinx.io.readString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * *Extensions* — `~/.claudebar/extensions/<id>/manifest.json`, read as definitions of origin
 * *Extension* (docs/features/extensions/design.md). The person's file stays as it is: each
 * section a definition can read becomes a data source, and they answer together.
 *
 * | Section | Becomes |
 * |---|---|
 * | `quotaGrid`, `costUsage` | a script fetch from the extension's folder + the usage mapping |
 * | `healthCheck` | a request; its failure shows as fetch health |
 * | `dailyUsage`, `metricsRow`, `statusBanner` | retired, and logged |
 */
internal object Extensions {
    /** `~/.claudebar/extensions`. */
    fun folder(home: String): String = Path(home, ".claudebar", "extensions").toString()

    /** Every extension in [root] that reads as a definition. One that doesn't is logged and left out. */
    fun catalog(root: String): List<ProviderDefinition> {
        val folders = runCatching { SystemFileSystem.list(Path(root)) }.getOrDefault(emptyList())
            .filter { !it.name.startsWith(".") }
            .sortedBy { it.name }
        return folders.mapNotNull { folder ->
            val manifest = runCatching {
                SystemFileSystem.source(Path(folder, "manifest.json")).buffered().use { it.readString() }
            }.getOrNull() ?: return@mapNotNull null
            try {
                definition(manifest, folder.toString())
            } catch (error: Exception) {
                AppLog.providers.error("Skipping extension ${folder.name}: ${error.message}")
                null
            }
        }
    }

    /** The definition an extension's manifest says, its scripts in [folder]. */
    fun definition(manifest: String, folder: String): ProviderDefinition {
        val m = Manifest.from(runCatching { Json.parseToJsonElement(manifest) }.getOrElse {
            throw DefinitionError("An extension's manifest is JSON: ${it.message}")
        })
        val config = m.config
        val sources = mutableListOf<DataSourceDefinition>()
        for (section in m.sections) {
            when (section.type) {
                "quotaGrid", "costUsage" -> {
                    val command = section.command ?: continue
                    sources += DataSourceDefinition(
                        kind = section.id, label = section.id,
                        fetch = Fetch.Script(ScriptCall(
                            run = command, folder = folder,
                            environment = config.filter { !it.isSecret }.associate { it.variable to "{{setting.${it.id}}}" },
                            secrets = config.filter { it.isSecret }.associate { it.variable to it.id },
                            timeout = section.timeout ?: 10.0,
                        )),
                        mapping = Mapping.Usage,
                    )
                }
                "healthCheck" -> {
                    val url = section.url ?: continue
                    sources += DataSourceDefinition(
                        kind = section.id, label = section.id,
                        fetch = Fetch.Http(HTTPRequest(url = url, method = "HEAD", timeout = section.timeout ?: 10.0)),
                        mapping = Mapping.Text(TextMapping(quotas = emptyList())),
                    )
                }
                else -> AppLog.providers.info("Extension ${m.id}: its ${section.type} section is no longer read")
            }
        }
        val first = sources.firstOrNull() ?: throw DefinitionErrors.noDataSources("ext-${m.id}")
        val definition = ProviderDefinition(
            profile = ProviderProfile(
                id = "ext-${m.id}", name = m.name,
                links = ProviderDefinition.Links(dashboardTemplate = m.dashboardURL?.ifEmpty { null }, status = m.statusPageURL?.ifEmpty { null }),
                look = ProviderLook(symbol = m.icon, color = m.primaryColor?.let(::shades)),
                origin = ProviderProfile.Origin.EXTENSION,
            ),
            dataSources = sources, defaultDataSource = first.kind, together = true, settings = config.map { it.setting },
        )
        // Parsed like any definition, so it keeps every law a definition keeps.
        return ProviderDefinition.parse(definition.toJson().toString(), ProviderProfile.Origin.EXTENSION)
    }

    /** `#FF6B35` as the same colour in light and dark. */
    private fun shades(hex: String): ProviderLook.Shades? {
        val digits = hex.trim('#')
        if (digits.length != 6) return null
        val value = digits.toIntOrNull(16) ?: return null
        val rgb = ProviderLook.RGB(((value shr 16) and 0xFF) / 255.0, ((value shr 8) and 0xFF) / 255.0, (value and 0xFF) / 255.0)
        return ProviderLook.Shades(rgb, rgb)
    }

    // The manifest, as extensions write it.

    private class Manifest(
        val id: String,
        val name: String,
        val icon: String?,
        val primaryColor: String?,
        val dashboardURL: String?,
        val statusPageURL: String?,
        val config: List<Field>,
        val sections: List<Section>,
    ) {
        companion object {
            fun from(json: JsonElement): Manifest {
                val o = json as? JsonObject ?: throw DefinitionError("A manifest is an object")
                return Manifest(
                    id = o.requireString("id", "manifest"),
                    name = o.requireString("name", "manifest"),
                    icon = o.optionalText("icon"),
                    primaryColor = (o.present("colors") as? JsonObject)?.optionalText("primary"),
                    dashboardURL = o.optionalText("dashboardURL"),
                    statusPageURL = o.optionalText("statusPageURL"),
                    config = (o.present("config") as? JsonArray)?.map(Field::from) ?: emptyList(),
                    sections = (o["sections"] as? JsonArray ?: throw DefinitionError("A manifest needs \"sections\"")).map(Section::from),
                )
            }
        }
    }

    private class Section(val id: String, val type: String, val command: String?, val url: String?, val timeout: Double?) {
        companion object {
            fun from(json: JsonElement): Section {
                val o = json as? JsonObject ?: throw DefinitionError("A section is an object")
                val probe = o["probe"] as? JsonObject ?: throw DefinitionError("A section needs \"probe\"")
                return Section(o.requireString("id", "section"), o.requireString("type", "section"), probe.optionalText("command"), probe.optionalText("url"), probe.double("timeout"))
            }
        }
    }

    private class Field(val id: String, val label: String, val type: String, val default: String?, val options: List<String>?) {
        val isSecret: Boolean get() = type == "secret"

        /** `apiKey` → `CLAUDEBAR_API_KEY`, `base-url` → `CLAUDEBAR_BASE_URL`: the names extension scripts read. */
        val variable: String
            get() = "CLAUDEBAR_" + id.replace("-", "_").replace(Regex("([a-z])([A-Z])"), "$1_$2").uppercase()

        val setting: Setting
            get() = Setting(
                id = id, label = label, default = default,
                kind = when (type) {
                    "secret" -> Setting.Kind.Secret
                    "number" -> Setting.Kind.Text("""^-?[0-9]+(\.[0-9]+)?$""")
                    "toggle" -> Setting.Kind.Choice(listOf(Setting.Option("true", "On"), Setting.Option("false", "Off")))
                    "choice" -> Setting.Kind.Choice((options ?: emptyList()).map { Setting.Option(it) })
                    "path" -> Setting.Kind.Path(mustExist = false)
                    else -> Setting.Kind.Text()
                },
            )

        companion object {
            fun from(json: JsonElement): Field {
                val o = json as? JsonObject ?: throw DefinitionError("A config field is an object")
                return Field(o.requireString("id", "config"), o.requireString("label", "config"), o.requireString("type", "config"), o.optionalText("default"), o.strings("options"))
            }
        }
    }
}

/** Text when present; anything else there is a manifest the extension's author must fix. */
private fun JsonObject.optionalText(key: String): String? {
    val value = present(key) ?: return null
    return (value as? JsonPrimitive)?.takeIf { it.isString }?.content ?: throw DefinitionError("\"$key\" is text")
}
