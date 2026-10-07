package com.tddworks.claudebar.datasources

// The ports: what lies outside the app that a data source needs (MODULAR_DESIGN §4).
// Each has a macOS adapter in macosMain; tests use fakes.

/** What a CLI printed, and how it ended. */
internal data class CLIResult(val output: String, val exitCode: Int = 0)

/** "Is this tool available?" and "run it and get my stats". */
internal interface CLIExecutor {
    fun locate(binary: String): String?

    /** Never blocks the caller's thread: a CLI can take tens of seconds. */
    suspend fun execute(
        binary: String,
        args: List<String>,
        input: String? = null,
        timeoutSeconds: Double = 30.0,
        workingDirectory: String? = null,
        autoResponses: Map<String, String> = emptyMap(),
    ): CLIResult
}

/** One HTTP request as a definition describes it. */
internal data class HttpCall(
    val url: String,
    val method: String = "GET",
    val headers: Map<String, String> = emptyMap(),
    val body: ByteArray? = null,
    val timeoutSeconds: Double = 30.0,
) {
    override fun equals(other: Any?) = other is HttpCall && other.url == url && other.method == method &&
        other.headers == headers && (other.body?.contentEquals(body ?: ByteArray(0)) ?: (body == null)) &&
        other.timeoutSeconds == timeoutSeconds

    override fun hashCode() = url.hashCode() * 31 + method.hashCode()
}

/** An HTTP endpoint. A transport failure throws; any status is an answer. */
internal interface NetworkClient {
    suspend fun send(call: HttpCall): Response
}

/** A JSON-RPC pipe to a process's stdin and stdout. */
internal interface RPCTransport {
    fun send(data: ByteArray)
    suspend fun receive(): ByteArray
    fun close()
}

/**
 * The vault — keys a person gave ClaudeBar for a provider. A definition names a key; the key
 * itself lives here, never in a definition, settings.json, a log line or an exported file.
 */
internal interface SecretStore {
    fun secret(name: String, provider: String): String?

    /** The vault as one login sees it: every key looked up under that login's id. */
    fun scoped(lineupId: String): SecretStore = object : SecretStore {
        override fun secret(name: String, provider: String) = this@SecretStore.secret(name, lineupId)
    }
}

/** The vault ClaudeBar writes as well as reads — *Add Account*'s key, forgotten on *Remove*. */
internal interface SecretVault : SecretStore {
    fun save(value: String, name: String, provider: String)
    fun delete(name: String, provider: String): Boolean
}

/** AWS CloudWatch: each dimension value's sum of each metric between two times. */
internal interface CloudWatchClient {
    suspend fun sums(
        namespace: String,
        dimension: String,
        metrics: List<String>,
        region: String,
        profile: String?,
        fromSeconds: Double,
        toSeconds: Double,
    ): Map<String, Map<String, Double>>
}

/** A cloud's price list (AWS). A price file a definition ships is data, not this. */
internal interface PriceCatalog {
    suspend fun prices(service: String, ids: List<String>): Map<String, Map<String, String>>
}

internal data class BrowserCookie(val name: String, val value: String)

/** The browsers' cookie stores. */
internal interface BrowserCookieReading {
    /** The cookies with these names for these domains (suffix match), one list per store, in import order. */
    fun stores(domains: List<String>, names: List<String>): List<List<BrowserCookie>>
}

/** The browsers' local storage. */
internal interface BrowserStorageReading {
    /** Every key and value kept for an origin, one map per profile, in import order. */
    fun stores(origin: String): List<Map<String, String>>
}

/** Runs a CLI's own sign-in, in a login's folder. */
internal interface SignInProcess {
    suspend fun run(
        executable: String,
        arguments: List<String>,
        environment: Map<String, String>,
        directory: String,
        timeoutSeconds: Double,
    ): Int
}

/** The folders added logins live in. */
internal interface LoginFolders {
    fun exists(folder: String): Boolean
    /** Makes a NEW private folder (0700) and its parents; throws when it is already there. */
    fun create(folder: String)
    fun delete(folder: String)
}
