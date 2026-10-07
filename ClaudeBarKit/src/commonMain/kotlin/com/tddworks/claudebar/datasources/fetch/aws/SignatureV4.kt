package com.tddworks.claudebar.datasources.fetch.aws

import com.tddworks.claudebar.diagnostics.isoTimestamp
import org.kotlincrypto.hash.sha2.SHA256
import org.kotlincrypto.macs.hmac.sha2.HmacSHA256

/** An AWS identity: a key pair, and the session token temporary credentials carry. */
internal data class AWSCredentials(val accessKeyId: String, val secretAccessKey: String, val sessionToken: String? = null) {
    override fun toString() = "AWSCredentials(${accessKeyId.take(4)}…)"
}

/** A request as SigV4 sees it: [path] and [query] not yet percent-encoded. */
internal data class SigningRequest(
    val method: String,
    val host: String,
    val path: String = "/",
    val query: List<Pair<String, String>> = emptyList(),
    val headers: List<Pair<String, String>> = emptyList(),
    val body: ByteArray = ByteArray(0),
) {
    override fun equals(other: Any?) = other is SigningRequest && other.method == method && other.host == host &&
        other.path == path && other.query == query && other.headers == headers && other.body.contentEquals(body)

    override fun hashCode() = method.hashCode() * 31 + path.hashCode()
}

/** What signing produced: the headers to send, and the steps in between, which AWS's test suite checks. */
internal data class Signature(
    val headers: List<Pair<String, String>>,
    val canonicalRequest: String,
    val stringToSign: String,
    val signature: String,
)

/**
 * AWS Signature Version 4 (header form), as AWS publishes it: the canonical request, the
 * string to sign, and an HMAC chain from the secret over date, region and service. The path
 * is normalised and encoded once, as for every service but S3.
 */
internal object SignatureV4 {
    private const val ALGORITHM = "AWS4-HMAC-SHA256"

    /**
     * Signs [request] at [nowSeconds] (since 1970). The result's headers — `X-Amz-Date`, the
     * session token, the body hash with [signBody], and `Authorization` — go out with the
     * request's own, which must include every header it sends but `Host`.
     */
    fun sign(
        request: SigningRequest,
        credentials: AWSCredentials,
        region: String,
        service: String,
        nowSeconds: Double,
        signBody: Boolean = false,
    ): Signature {
        val amzDate = amzDate(nowSeconds)
        val day = amzDate.take(8)
        val bodyHash = hex(SHA256().digest(request.body))
        val added = buildList {
            add("X-Amz-Date" to amzDate)
            credentials.sessionToken?.let { add("X-Amz-Security-Token" to it) }
            if (signBody) add("X-Amz-Content-Sha256" to bodyHash)
        }
        val signed = (listOf("Host" to request.host) + request.headers + added)
            .groupBy({ it.first.lowercase() }, { normalizedValue(it.second) })
            .entries.sortedBy { it.key }
        val signedHeaders = signed.joinToString(";") { it.key }
        val canonicalRequest = listOf(
            request.method.uppercase(),
            canonicalPath(request.path),
            canonicalQuery(request.query),
            signed.joinToString("") { "${it.key}:${it.value.joinToString(",")}\n" },
            signedHeaders,
            bodyHash,
        ).joinToString("\n")

        val scope = "$day/$region/$service/aws4_request"
        val stringToSign = listOf(ALGORITHM, amzDate, scope, hex(SHA256().digest(canonicalRequest.encodeToByteArray()))).joinToString("\n")
        val key = listOf(day, region, service, "aws4_request")
            .fold("AWS4${credentials.secretAccessKey}".encodeToByteArray()) { key, part -> hmac(key, part) }
        val signature = hex(hmac(key, stringToSign))
        val authorization = "$ALGORITHM Credential=${credentials.accessKeyId}/$scope, SignedHeaders=$signedHeaders, Signature=$signature"
        return Signature(added + ("Authorization" to authorization), canonicalRequest, stringToSign, signature)
    }

    /** `20150830T123600Z`. */
    fun amzDate(nowSeconds: Double): String =
        isoTimestamp(kotlin.math.floor(nowSeconds).toLong() * 1000).substringBefore('.').filter { it != '-' && it != ':' } + "Z"

    /** RFC 3986: everything but `A–Z a–z 0–9 - . _ ~` as `%XX` of its UTF-8 bytes. */
    fun encode(text: String, keepSlash: Boolean = false): String = buildString {
        for (byte in text.encodeToByteArray()) {
            val char = (byte.toInt() and 0xFF).toChar()
            if (char in 'A'..'Z' || char in 'a'..'z' || char in '0'..'9' || char in "-._~" || (keepSlash && char == '/')) append(char)
            else append('%').append(HEX[(byte.toInt() shr 4) and 0xF]).append(HEX[byte.toInt() and 0xF])
        }
    }

    private fun canonicalPath(path: String): String {
        val segments = mutableListOf<String>()
        for (segment in path.split('/')) when (segment) {
            "", "." -> Unit
            ".." -> segments.removeLastOrNull()
            else -> segments += segment
        }
        val trailing = path.length > 1 && path.endsWith("/") && segments.isNotEmpty()
        return "/" + segments.joinToString("/") { encode(it) } + if (trailing) "/" else ""
    }

    private fun canonicalQuery(query: List<Pair<String, String>>): String =
        query.map { encode(it.first) to encode(it.second) }
            .sortedWith(compareBy({ it.first }, { it.second }))
            .joinToString("&") { "${it.first}=${it.second}" }

    /** Trimmed, with runs of spaces made one. */
    private fun normalizedValue(value: String) = value.trim().replace(Regex(" +"), " ")

    private fun hmac(key: ByteArray, data: String): ByteArray = HmacSHA256(key).doFinal(data.encodeToByteArray())

    private fun hex(bytes: ByteArray) = bytes.joinToString("") { (it.toInt() and 0xFF).toString(16).padStart(2, '0') }

    private const val HEX = "0123456789ABCDEF"
}
