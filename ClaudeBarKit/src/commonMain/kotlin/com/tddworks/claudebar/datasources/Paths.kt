package com.tddworks.claudebar.datasources

import kotlinx.io.files.Path
import kotlinx.io.files.SystemFileSystem
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonPrimitive

/**
 * A place on disk a definition names: one path, or a list. A `*` stands for part of one
 * folder or file name. Written back the way it was given. [Paths.resolve] says which file it is.
 */
@Serializable(with = PathPatternSerializer::class)
internal data class PathPattern(val places: List<String>) {
    constructor(path: String) : this(listOf(path))

    init {
        require(places.isNotEmpty()) { "A path list needs at least one path" }
    }

    /** As Settings shows it. */
    override fun toString() = places.joinToString(" · ")

    fun map(transform: (String) -> String) = PathPattern(places.map(transform))

    fun toJson(): JsonElement =
        if (places.size == 1) JsonPrimitive(places[0]) else JsonArray(places.map(::JsonPrimitive))

    companion object {
        fun from(json: JsonElement): PathPattern = when {
            json is JsonPrimitive && json.isString -> PathPattern(json.content)
            json is JsonArray && json.isNotEmpty() -> PathPattern(json.map { (it as JsonPrimitive).content })
            else -> throw DefinitionError("A path is text or a non-empty list of text")
        }
    }
}

internal object PathPatternSerializer : KSerializer<PathPattern> {
    override val descriptor: SerialDescriptor = JsonElement.serializer().descriptor
    override fun deserialize(decoder: Decoder) = PathPattern.from((decoder as JsonDecoder).decodeJsonElement())
    override fun serialize(encoder: Encoder, value: PathPattern) = (encoder as JsonEncoder).encodeJsonElement(value.toJson())
}

/**
 * Which file on disk a definition means — the one owner of that rule (ENGINE_DESIGN §2.9).
 * `~/…` and `${VARIABLE:-default}/…` expand; a `*` matches within one name; of every file that
 * matches, in every place, the most recently changed. When none matches, the first place as
 * written, which is missing.
 */
internal object Paths {
    fun resolve(pattern: PathPattern, home: String, environment: (String) -> String?): String {
        val expanded = pattern.places.map { expand(it, home, environment) }
        if (expanded.size == 1 && '*' !in expanded[0]) return expanded[0]
        return expanded.flatMap(::matches).maxByOrNull { modifiedSeconds(it) ?: Double.NEGATIVE_INFINITY } ?: expanded[0]
    }

    fun expand(path: String, home: String, environment: (String) -> String?): String {
        var result = path
        if (result.startsWith("\${")) {
            val close = result.indexOf('}')
            if (close > 0) {
                val parts = result.substring(2, close).split(":-", limit = 2)
                val value = environment(parts[0])?.takeIf { it.isNotEmpty() } ?: parts.getOrElse(1) { "" }
                result = value + result.substring(close + 1)
            }
        }
        if (result == "~") return home
        if (result.startsWith("~/")) return home.trimEnd('/') + "/" + result.removePrefix("~/")
        return result
    }

    private fun matches(path: String): List<String> {
        if ('*' !in path) return if (SystemFileSystem.exists(Path(path))) listOf(path) else emptyList()
        var found = listOf(if (path.startsWith("/")) "/" else "")
        for (name in path.split('/').filter { it.isNotEmpty() }) {
            found = found.flatMap { folder ->
                if ('*' !in name) listOf("$folder$name/")
                else runCatching { SystemFileSystem.list(Path(folder.ifEmpty { "." })) }.getOrDefault(emptyList())
                    .map { it.name }.filter { glob(name, it) }.sorted().map { "$folder$it/" }
            }
        }
        return found.map { it.dropLast(1) }.filter { SystemFileSystem.exists(Path(it)) }
    }

    /** `*` matches any run within one name; everything else is literal. */
    fun glob(pattern: String, name: String): Boolean {
        val parts = pattern.split('*')
        if (parts.size == 1) return pattern == name
        if (!name.startsWith(parts.first()) || !name.endsWith(parts.last())) return false
        var at = parts.first().length
        val end = name.length - parts.last().length
        if (at > end) return false
        for (part in parts.subList(1, parts.size - 1)) {
            val index = name.indexOf(part, at).takeIf { it >= 0 && it + part.length <= end } ?: return false
            at = index + part.length
        }
        return true
    }
}

/** When a file last changed, in seconds since 1970; null when it doesn't exist. */
internal expect fun modifiedSeconds(path: String): Double?
