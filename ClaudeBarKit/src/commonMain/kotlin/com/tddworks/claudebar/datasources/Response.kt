package com.tddworks.claudebar.datasources

/** What came back from a fetch, before anyone read it — what *Test Connection* shows. */
public class Response(
    /** The HTTP status, when the fetch was over HTTP. */
    val status: Int? = null,
    headers: Map<String, String> = emptyMap(),
    val body: ByteArray,
) {
    /** Lowercased names, so a mapping asks case-insensitively; the first of two spellings wins. */
    val headers: Map<String, String> = headers.entries.reversed().associate { it.key.lowercase() to it.value }

    constructor(text: String) : this(body = text.encodeToByteArray())

    val text: String get() = body.decodeToString()

    fun header(name: String): String? = headers[name.lowercase()]

    override fun equals(other: Any?) =
        other is Response && other.status == status && other.headers == headers && other.body.contentEquals(body)

    override fun hashCode() = (status ?: 0) * 31 + body.contentHashCode()
}
