package com.tddworks.claudebar.datasources

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull

/**
 * How definitions are read: unknown keys ignored (a newer definition still loads), defaults
 * left out when written. Definitions decode from `JsonElement` by hand where a shape has
 * more than one spelling — a closed sum's single tag, a string-or-object, a string-or-list.
 */
internal val DefinitionJson = Json {
    ignoreUnknownKeys = true
    explicitNulls = false
    isLenient = false
}

/** A definition that can't be read, saying where and why. */
internal class DefinitionError(message: String) : IllegalArgumentException(message)

/** The one tag present among [known] — a closed sum's `{ "http": { … } }` — or a DefinitionError naming them. */
internal fun JsonObject.singleTag(known: List<String>, type: String): String {
    val present = keys.filter { it in known }
    if (present.size != 1) {
        throw DefinitionError("$type needs exactly one of ${known.joinToString(", ")}; found ${keys.toList()}")
    }
    return present.single()
}

internal fun JsonElement.objectOrNull(): JsonObject? = this as? JsonObject
internal fun JsonElement.arrayOrNull(): JsonArray? = this as? JsonArray

internal fun JsonObject.string(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
internal fun JsonObject.requireString(key: String, type: String): String =
    string(key) ?: throw DefinitionError("$type needs \"$key\"")
internal fun JsonObject.bool(key: String): Boolean? = (this[key] as? JsonPrimitive)?.booleanOrNull
internal fun JsonObject.double(key: String): Double? = (this[key] as? JsonPrimitive)?.takeUnless { it.isString }?.doubleOrNull
internal fun JsonObject.int(key: String): Int? = (this[key] as? JsonPrimitive)?.takeUnless { it.isString }?.intOrNull
internal fun JsonObject.strings(key: String): List<String>? =
    (this[key] as? JsonArray)?.map { (it as? JsonPrimitive)?.content ?: throw DefinitionError("\"$key\" holds only text") }
internal fun JsonObject.stringMap(key: String): Map<String, String>? =
    (this[key] as? JsonObject)?.mapValues { (it.value as? JsonPrimitive)?.content ?: it.value.toString() }
