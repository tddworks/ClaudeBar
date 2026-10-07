package com.tddworks.claudebar.datasources

import com.tddworks.claudebar.datasources.lookup.JSONFileReader
import com.tddworks.claudebar.datasources.mapping.Mapping
import com.tddworks.claudebar.diagnostics.AppLog
import com.tddworks.claudebar.quotas.UsageError
import com.tddworks.claudebar.quotas.UsageSnapshot

/**
 * ONE type that fetches for every provider: its definition, made live by `DataSources.make` with
 * only the connection its fetch needs. `fetchUsage()` is *Fetching usage data…*: look up the key,
 * fetch, map. `fetchResponse()` is *Test Connection*: it stops before mapping.
 */
internal class DataSource(
    val definition: DataSourceDefinition,
    val providerId: String,
    private val credentials: CredentialFinding?,
    private val refresher: CredentialRefreshing?,
    private val fetcher: Fetching,
    private val mapper: Reading,
    private val contextFiles: Map<String, JSONFileReader>,
    private val recoveries: Map<String, Recovering>,
    private val requiredFiles: List<String> = emptyList(),
    private val fileExists: (String) -> Boolean,
    private val now: () -> Double,
) {
    private val memory = UsageMemory()

    val kind: String get() = definition.kind

    /** How long a fetched usage is served again — also the provider's background refresh floor. */
    val cacheTTL: Double? get() = definition.cache?.ttl

    /** The data source that takes over when this one finds no key, or null when it has its key. */
    val handOffWithoutKey: String?
        get() = if (hasKey) null else definition.fallbackOn[UsageError.AuthenticationRequired.tag]

    /** Whether the key lookup finds a key — *OAuth credentials found*; true when none is needed. */
    val hasKey: Boolean get() = credentials.let { it == null || runCatching { it.find() }.getOrNull() != null }

    /** *Configured*: the files it needs exist, the key answers and belongs to the expected account, and the CLI exists. */
    fun isReady(): Boolean {
        if (!requiredFiles.all(fileExists)) return false
        var credential: Credential? = null
        val credentials = credentials
        if (credentials != null) {
            credential = (runCatching { credentials.find() }.getOrNull() ?: return false).credential
        }
        return isExpectedLogin(credential) && fetcher.isReady()
    }

    /** What an identity field holds — the account id, the email — never a token; null when nothing answers. */
    fun value(of: IdentityField): String? {
        val credential = runCatching { credentials?.find() }.getOrNull()?.credential
        return read(of, credential?.let { Credential(withoutSecrets(it.values)) })
    }

    /** Looks up the key and fetches; nothing is mapped or saved. Throws a DataSourceError naming the step. */
    suspend fun fetchResponse(): Response = fetch().first

    /**
     * *Fetching usage data…* — served from the cache while it is fresh, and refused without a
     * request while a rate limit lasts. Throws a DataSourceError naming the step that failed.
     */
    suspend fun fetchUsage(): UsageSnapshot {
        cacheTTL?.let { ttl -> memory.snapshot(ttl, now())?.let { return it } }
        memory.rateLimit(now())?.let { throw DataSourceError(DataSourceError.Step.FETCH, UsageError.RateLimited(it)) }
        try {
            val usage = fetchAndRead(recovering = true)
            if (cacheTTL != null) memory.remember(usage, now())
            return usage
        } catch (error: DataSourceError) {
            (error.reason as? UsageError.RateLimited)?.let { memory.rememberRateLimit(it.retryAtSeconds) }
            throw error
        }
    }

    /** *Map fields*' live card: reads a response already fetched. */
    fun read(response: Response): UsageSnapshot = read(response, null)

    private suspend fun fetchAndRead(recovering: Boolean): UsageSnapshot {
        val (response, credential) = fetch()
        return try {
            read(response, credential)
        } catch (failure: DataSourceError) {
            val recovery = recoveries[failure.reason.tag]
            if (!recovering || recovery == null || !recovery.recover()) throw failure
            AppLog.probes.info("$providerId $kind: recovered from ${failure.reason.tag}, trying once more")
            fetchAndRead(recovering = false)
        }
    }

    private fun read(response: Response, credential: Credential?): UsageSnapshot {
        val facts = MappingFacts(visibleCredential(credential), contextFiles.mapValues { it.value.fields() })
        return try {
            mapper.read(response, facts, providerId)
        } catch (error: Throwable) {
            throw DataSourceError.wrap(error, DataSourceError.Step.MAPPING)
        }
    }

    /** What a mapping may read of the credential — never a token. A script sees only the values it names. */
    private fun visibleCredential(credential: Credential?): Map<String, String> {
        val values = withoutSecrets(credential?.values ?: return emptyMap())
        val script = definition.mapping as? Mapping.Script ?: return values
        return values.filterKeys { it in script.mapping.credential }
    }

    private fun withoutSecrets(values: Map<String, String>) = values.filterKeys { it !in SECRETS }

    private fun read(field: IdentityField, credential: Credential?): String? = when (field) {
        is IdentityField.CredentialValue -> credential?.get(field.name)
        is IdentityField.ContextValue -> contextFiles[field.file]?.fields()?.get(field.field)
    }

    private fun isExpectedLogin(credential: Credential?): Boolean {
        val identity = definition.identity ?: return true
        return read(identity.field, credential) == identity.equals
    }

    /** Fails closed when the login now belongs to another account. */
    private fun checkIdentity(credential: Credential?) {
        val identity = definition.identity ?: return
        if (!isExpectedLogin(credential)) throw DataSourceError(DataSourceError.Step.LOOKUP, UsageError.SessionExpired(identity.hint))
    }

    private suspend fun fetch(): Pair<Response, Credential?> {
        for (file in requiredFiles) {
            if (!fileExists(file)) {
                // ClaudeBar never starts a login itself (#216).
                AppLog.probes.error("$providerId $kind: no $file — refusing to run")
                throw DataSourceError(DataSourceError.Step.LOOKUP, UsageError.AuthenticationRequired)
            }
        }
        val found = lookUp()
        checkIdentity(found?.credential)
        val result = fetchWith(found)
        if (definition.identity != null) checkIdentity(runCatching { credentials?.find() }.getOrNull()?.credential)
        return result
    }

    private suspend fun fetchWith(initial: FoundCredential?): Pair<Response, Credential?> {
        var found = initial
        val refresher = refresher
        if (refresher != null && found != null && refresher.isDue(found.credential)) {
            val current = found
            try {
                found = refreshed(current, refresher)
            } catch (error: DataSourceError) {
                val rotated = rotated(current)
                when {
                    // Another program — the CLI that owns the credential — already refreshed it.
                    rotated != null -> found = rotated
                    error.reason is UsageError.SessionExpired -> throw error
                    // A proactive refresh that fails is not fatal: the token we have may still work.
                    else -> AppLog.probes.warning("$providerId $kind: refresh failed, trying the current token")
                }
            }
        }
        return try {
            fetcher.fetch(found?.credential) to found?.credential
        } catch (refused: HTTPStatusError) {
            val current = found
            if (refresher == null || current == null || refused.status !in refresher.retryStatuses) throw fetchError(refused)
            AppLog.probes.info("$providerId $kind: HTTP ${refused.status}, refreshing the token once")
            val renewed = try {
                refreshed(current, refresher)
            } catch (error: Throwable) {
                rotated(current) ?: throw error
            }
            try {
                fetcher.fetch(renewed.credential) to renewed.credential
            } catch (error: Throwable) {
                throw fetchError(error)
            }
        } catch (error: DataSourceError) {
            throw error
        } catch (error: Throwable) {
            throw fetchError(error)
        }
    }

    private fun lookUp(): FoundCredential? {
        val credentials = credentials ?: return null
        val found = try {
            credentials.find()
        } catch (error: Throwable) {
            throw DataSourceError.wrap(error, DataSourceError.Step.LOOKUP)
        }
        return found ?: throw DataSourceError(DataSourceError.Step.LOOKUP, UsageError.AuthenticationRequired)
    }

    /** The credential looked up again, when its token is no longer [current]'s. */
    private fun rotated(current: FoundCredential): FoundCredential? {
        val fresh = runCatching { credentials?.find() }.getOrNull() ?: return null
        if (fresh.credential.token == current.credential.token) return null
        AppLog.probes.info("$providerId $kind: the credential changed on disk; using the new one")
        return fresh
    }

    /** Refreshes the token and writes it back where it was found — or, when its owner renewed it, reads it again. */
    private suspend fun refreshed(found: FoundCredential, refresher: CredentialRefreshing): FoundCredential {
        val credential = try {
            refresher.refresh(found.credential)
        } catch (error: Throwable) {
            throw DataSourceError.wrap(error, DataSourceError.Step.LOOKUP)
        }
        if (!refresher.writesBack) {
            return runCatching { credentials?.find() }.getOrNull()
                ?: throw DataSourceError(DataSourceError.Step.LOOKUP, UsageError.AuthenticationRequired)
        }
        found.save?.invoke(credential)
        return found.copy(credential = credential)
    }

    /** A worker's failure, worded by the definition. */
    private fun fetchError(error: Throwable): DataSourceError {
        if (error is DataSourceError) return error
        val failure = error as? ReportedFailure ?: return DataSourceError.wrap(error, DataSourceError.Step.FETCH)
        return DataSourceError(DataSourceError.Step.FETCH, definition.reason(failure))
    }

    private companion object {
        val SECRETS = setOf("token", "refreshToken", "idToken")
    }
}
