package com.tddworks.claudebar.datasources

/** What a key lookup found: named values — `token`, `refreshToken`, `account`, `email` … */
internal data class Credential(val values: Map<String, String>) {
    val token: String? get() = values["token"]

    operator fun get(name: String): String? = values[name]

    fun with(name: String, value: String?): Credential =
        Credential(if (value == null) values - name else values + (name to value))
}

/** A credential found, and how to write a refreshed one back where it came from. */
internal data class FoundCredential(val credential: Credential, val save: ((Credential) -> Unit)? = null)

/** What a mapping may read besides the response: the credential values it may see, each context file's fields. */
internal data class MappingFacts(
    val credential: Map<String, String> = emptyMap(),
    val context: Map<String, Map<String, String>> = emptyMap(),
)
