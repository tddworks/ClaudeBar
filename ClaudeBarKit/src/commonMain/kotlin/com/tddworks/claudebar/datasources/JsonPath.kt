package com.tddworks.claudebar.datasources

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull

/**
 * The small path dialect definitions use (TARGET_ARCHITECTURE §8):
 * - `$.a.b` from the document's root; `a.b` from the current object (inside `at` or `each`)
 * - `$header.name`, `$credential.name` (never a secret), `$context.file.field`, `$key`
 * - a numeric component indexes an array; a trailing `[*]` is ignored
 */
internal class JsonScope private constructor(
    val root: JsonElement?,
    val current: JsonElement?,
    private val headers: Map<String, String>,
    private val key: String?,
    private val credential: Map<String, String>,
    private val context: Map<String, Map<String, String>>,
) {
    constructor(
        root: JsonElement?,
        headers: Map<String, String> = emptyMap(),
        credential: Map<String, String> = emptyMap(),
        context: Map<String, Map<String, String>> = emptyMap(),
    ) : this(root, root, headers, null, credential, context)

    /** The same document, reading relative paths from [to] — which may be missing. */
    fun moved(to: JsonElement?, key: String? = null) = JsonScope(root, to, headers, key ?: this.key, credential, context)

    fun value(path: String): JsonElement? = when {
        path == "\$key" -> key?.let(::JsonPrimitive)
        path.startsWith("\$credential.") -> credential[path.removePrefix("\$credential.")]?.let(::JsonPrimitive)
        path.startsWith("\$context.") -> path.removePrefix("\$context.").split('.', limit = 2)
            .takeIf { it.size == 2 }?.let { context[it[0]]?.get(it[1]) }?.let(::JsonPrimitive)
        path.startsWith("\$header.") -> headers[path.removePrefix("\$header.").lowercase()]?.let(::JsonPrimitive)
        path == "$" -> root
        path.startsWith("$.") -> JsonPath.walk(root, JsonPath.components(path.removePrefix("$.")))
        else -> JsonPath.walk(current, JsonPath.components(path))
    }

    fun number(path: String): Double? = JsonPath.number(value(path))
    fun string(path: String): String? = JsonPath.string(value(path))
}

internal object JsonPath {
    fun components(path: String): List<String> =
        path.removePrefix("$.").removeSuffix("[*]").split('.').filter { it.isNotEmpty() }

    fun walk(value: JsonElement?, components: List<String>): JsonElement? {
        var current = value
        for (component in components) {
            current = when (current) {
                is JsonObject -> current[component]
                is JsonArray -> component.toIntOrNull()?.let { current.getOrNull(it) }
                else -> return null
            }
            if (current == null || current is JsonNull) return null
        }
        return current
    }

    /** A number, or text that reads as one; never a yes/no, never infinite. */
    fun number(value: JsonElement?): Double? {
        val primitive = value as? JsonPrimitive ?: return null
        if (primitive is JsonNull) return null
        val number = if (primitive.isString) primitive.content.trim().toDoubleOrNull()
        else if (primitive.booleanOrNull != null) null
        else primitive.content.toDoubleOrNull()
        return number?.takeIf { it.isFinite() }
    }

    /** Text, or a number as text the way Foundation prints it (`1.0` → `1`, yes → `1`). */
    fun string(value: JsonElement?): String? {
        val primitive = value as? JsonPrimitive ?: return null
        if (primitive is JsonNull) return null
        if (primitive.isString) return primitive.content
        primitive.booleanOrNull?.let { return if (it) "1" else "0" }
        val double = primitive.content.toDoubleOrNull() ?: return primitive.content
        return if (double == kotlin.math.floor(double) && kotlin.math.abs(double) < 1e15) double.toLong().toString()
        else double.toString()
    }

    /** Writes [value] at a `$.a.b` path, creating objects on the way and keeping every other field. */
    fun set(value: JsonElement, path: String, document: JsonObject): JsonObject = set(value, components(path), document)

    private fun set(value: JsonElement, components: List<String>, document: JsonObject): JsonObject {
        val first = components.firstOrNull() ?: return document
        val updated = document.toMutableMap()
        updated[first] = if (components.size == 1) value
        else set(value, components.drop(1), document[first] as? JsonObject ?: JsonObject(emptyMap()))
        return JsonObject(updated)
    }
}

/** `{{<scope>.<name>}}` in a definition's strings. */
internal object Placeholders {
    fun fill(text: String, values: Map<String, String>, scope: String): String =
        names(text, scope).fold(text) { acc, name -> values[name]?.let { acc.replace("{{$scope.$name}}", it) } ?: acc }

    fun names(text: String, scope: String): List<String> {
        val opening = "{{$scope."
        val names = mutableListOf<String>()
        var rest = text
        while (true) {
            val start = rest.indexOf(opening).takeIf { it >= 0 } ?: break
            val end = rest.indexOf("}}", start + opening.length).takeIf { it >= 0 } ?: break
            names += rest.substring(start + opening.length, end)
            rest = rest.substring(end + 2)
        }
        return names
    }
}

/** RFC 7396 JSON Merge Patch: an object merges key by key, null removes, anything else replaces. */
internal fun JsonElement.merged(patch: JsonElement): JsonElement {
    if (patch !is JsonObject) return patch
    val result = (this as? JsonObject)?.toMutableMap() ?: mutableMapOf()
    for ((key, change) in patch) {
        if (change is JsonNull) result.remove(key) else result[key] = (result[key] ?: JsonNull).merged(change)
    }
    return JsonObject(result)
}

/** The same value with [transform] applied to every string, keys excepted. */
internal fun JsonElement.mapStrings(transform: (String) -> String): JsonElement = when (this) {
    is JsonObject -> JsonObject(mapValues { it.value.mapStrings(transform) })
    is JsonArray -> JsonArray(map { it.mapStrings(transform) })
    is JsonPrimitive -> if (isString) JsonPrimitive(transform(content)) else this
}
