package com.tddworks.claudebar.providers

import com.tddworks.claudebar.diagnostics.AppLog
import kotlinx.io.buffered
import kotlinx.io.files.Path
import kotlinx.io.files.SystemFileSystem
import kotlinx.io.readString
import kotlinx.io.writeString
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid

/**
 * Where definitions live, and the one place they are found (TARGET_ARCHITECTURE §10): the
 * built-ins, the providers people make in `~/.claudebar/providers/<id>.json` (origin
 * **custom**), and extensions in `~/.claudebar/extensions`. A definition on disk is a
 * provider; no code lists one. Keys never live here — a definition names a key, the vault holds it.
 */
internal class ProviderCatalog(
    val builtIns: BuiltInDefinitions,
    /** `~/.claudebar/providers`. */
    val directory: String,
    /** `~/.claudebar/extensions`. */
    val extensions: String,
) {
    /**
     * Every definition, built-in, custom and extension, in lineup order: by each one's `order`,
     * then by name. A built-in's id is the built-in's — another file using it is left out. A
     * file that doesn't parse is logged and left out; the rest load.
     */
    fun detect(): List<ProviderDefinition> {
        val builtIns = builtIns.all.values.toList()
        val reserved = builtIns.map { it.id }.toSet()
        val others = (custom() + Extensions.catalog(extensions)).filter { definition ->
            if (definition.id !in reserved) return@filter true
            AppLog.providers.error("Skipping ${definition.id} from ${definition.profile.origin.tag}: a built-in has that id")
            false
        }
        val seen = mutableSetOf<String>()
        return (builtIns + others)
            .filter { seen.add(it.id) }
            .sortedWith(compareBy<ProviderDefinition>({ it.order ?: Int.MAX_VALUE }, { it.profile.name.lowercase() }, { it.id }))
    }

    /** Every custom definition that parses. One that doesn't is skipped and logged — a broken file never takes the others down. */
    fun custom(): List<ProviderDefinition> {
        val names = runCatching { SystemFileSystem.list(Path(directory)).map { it.name } }.getOrDefault(emptyList())
        return names.filter { it.endsWith(".json") }.sorted().mapNotNull { name ->
            try {
                val text = SystemFileSystem.source(Path(directory, name)).buffered().use { it.readString() }
                ProviderDefinition.parse(text, ProviderProfile.Origin.CUSTOM)
            } catch (error: Exception) {
                AppLog.providers.error("Skipping custom provider $name: ${error.message}")
                null
            }
        }
    }

    /** *Save*: writes the definition. A built-in's id is refused. */
    fun add(definition: ProviderDefinition) {
        if (builtIns[definition.id] != null) throw DefinitionErrors.duplicateProvider(definition.id)
        definition.validate()
        SystemFileSystem.createDirectories(Path(directory))
        val file = file(definition.id)
        val writing = Path("$file.writing")
        SystemFileSystem.sink(writing).buffered().use { it.writeString(definition.exported()) }
        SystemFileSystem.atomicMove(writing, file)
        AppLog.providers.info("Saved custom provider ${definition.id}")
    }

    /** *Delete*: removes the definition's file. */
    fun remove(id: String) {
        val file = file(id)
        if (!SystemFileSystem.exists(file)) return
        SystemFileSystem.delete(file)
        AppLog.providers.info("Removed custom provider $id")
    }

    /** A new id, minted once: `custom-<name>-<random>` — never derived from the name alone, never a built-in's or a saved one's. */
    @OptIn(ExperimentalUuidApi::class)
    fun mintId(name: String): String {
        val slug = buildString {
            for (character in name.lowercase()) {
                val kept = if (character.isLetter() || character.isDigit()) character else '-'
                if (kept != '-' || lastOrNull() != '-') append(kept)
            }
        }.trim('-')
        while (true) {
            val id = "custom-${slug.ifEmpty { "provider" }}-${Uuid.random().toString().take(6).lowercase()}"
            if (builtIns[id] == null && !SystemFileSystem.exists(file(id))) return id
        }
    }

    /**
     * *Import provider*: reads a shared file and says what it would do, before anything is saved
     * or run (USER_JOURNEYS F10). Its id is kept unless a built-in or a saved provider has it.
     */
    fun review(file: String): ImportReview {
        var definition = ProviderDefinition.parse(file, ProviderProfile.Origin.CUSTOM)
        if (builtIns[definition.id] != null || custom().any { it.id == definition.id }) {
            definition = definition.renamed(mintId(definition.profile.name))
        }
        return ImportReview(definition, definition.keyDestinations, definition.commands, definition.neededSettings)
    }

    /** *Add*: saves what the review showed. */
    fun import(review: ImportReview): ProviderDefinition {
        add(review.definition)
        return review.definition
    }

    private fun file(id: String) = Path(directory, "$id.json")

    companion object {
        fun userDirectory(home: String): String = Path(home, ".claudebar", "providers").toString()
    }
}
