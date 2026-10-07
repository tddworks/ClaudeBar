package com.tddworks.claudebar.providers

import kotlinx.io.buffered
import kotlinx.io.files.Path
import kotlinx.io.files.SystemFileSystem
import kotlinx.io.readString

/**
 * The files shipped with the app beside the definitions — `codex.json`, `codex-usage.js`, a
 * price list. A port, so the composition root says where they are (the app bundle's folder
 * today; compiled-in sources later, MODULAR_DESIGN §4).
 */
internal interface DefinitionFiles {
    /** Every file's name, as `<name>.<extension>`. */
    fun names(): List<String>

    /** A file's text, or null when there is no such file or it can't be read. */
    fun read(name: String): String?
}

/** The definition files in one folder on disk. */
internal class FolderDefinitionFiles(private val folder: String) : DefinitionFiles {
    override fun names(): List<String> = runCatching {
        SystemFileSystem.list(Path(folder)).map { it.name }.sorted()
    }.getOrDefault(emptyList())

    override fun read(name: String): String? = runCatching {
        SystemFileSystem.source(Path(folder, name)).buffered().use { it.readString() }
    }.getOrNull()
}

/**
 * The built-in definitions, by id, read once from their files. A file that doesn't parse is
 * no built-in: the files hold scripts and price lists beside the definitions.
 */
internal class BuiltInDefinitions(private val files: DefinitionFiles) {
    /** Every built-in definition, by id. */
    val all: Map<String, ProviderDefinition> by lazy {
        files.names().filter { it.endsWith(".json") }.mapNotNull { name ->
            files.read(name)?.let { text -> runCatching { ProviderDefinition.parse(text) }.getOrNull() }
        }.associateBy { it.id }
    }

    operator fun get(id: String): ProviderDefinition? = all[id]

    /** The built-in definition [id] names, parsed afresh. */
    fun definition(id: String): ProviderDefinition = ProviderDefinition.parse(text(id))

    /** The built-in definition's JSON, as shipped. */
    fun text(id: String): String = files.read("$id.json") ?: throw DefinitionErrors.missingFile(id)

    /** The built-in definition a lineup id belongs to — `codex.<account>` belongs to `codex`. */
    fun forLineupId(id: String): ProviderDefinition? = all[id] ?: all[id.substringBefore('.')]

    /** A mapping script or price file shipped beside the definitions; a name without an extension is a `.js`. */
    fun script(file: String): String? = files.read(if (file.substringAfterLast('/').contains('.')) file else "$file.js")
}
