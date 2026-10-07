package com.tddworks.claudebar.datasources.lookup

import com.tddworks.claudebar.datasources.BrowserCookieReading
import com.tddworks.claudebar.datasources.BrowserStorageReading
import com.tddworks.claudebar.datasources.CLICall
import com.tddworks.claudebar.datasources.CLIExecutor
import com.tddworks.claudebar.datasources.CredentialFinding
import com.tddworks.claudebar.datasources.CredentialRefreshing
import com.tddworks.claudebar.datasources.NetworkClient
import com.tddworks.claudebar.datasources.SQLiteCall
import com.tddworks.claudebar.datasources.SecretStore

/**
 * The one place a case of [CredentialLookup] meets the connection it needs — what the data
 * sources' factory calls, so it never names a reader. Each connection is a port; macosMain's
 * `SystemLookup` hands in the real ones.
 */
internal class CredentialFinders(
    private val providerId: String,
    private val home: String,
    private val environment: (String) -> String?,
    private val security: SecurityTool,
    private val secrets: SecretStore?,
    private val database: SQLiteReading,
    private val browserCookies: BrowserCookieReading,
    private val browserStorage: BrowserStorageReading,
    /** The person's login shell, for a lookup that asks for it. */
    private val loginShell: ((String) -> String?)? = null,
) {
    fun reader(lookup: CredentialLookup): CredentialFinding = when (lookup) {
        is CredentialLookup.Environment -> EnvironmentReader(lookup.name, environment, if (lookup.loginShell) loginShell else null)
        is CredentialLookup.JsonFile -> JSONFileReader(lookup.file, home, environment)
        is CredentialLookup.Keychain -> KeychainReader(lookup.item, security)
        is CredentialLookup.Setting -> SettingReader(lookup.name, providerId, secrets)
        is CredentialLookup.Refined -> RefinedReader(reader(lookup.base), lookup.refinement)
        is CredentialLookup.Sqlite -> SQLiteReader(lookup.database, database, home, environment)
        is CredentialLookup.BrowserCookies -> BrowserCookieReader(lookup.query, browserCookies)
        is CredentialLookup.BrowserStorage -> BrowserStorageReader(lookup.query, browserStorage)
        is CredentialLookup.FirstOf -> FirstOfReader(lookup.lookups.map(::reader))
        // A refresh nested inside `firstOf` is refreshed by the outer data source only; reading still works.
        is CredentialLookup.Refreshing -> reader(lookup.base)
    }

    /** A context file's reader: its fields, never requiring a token. */
    fun contextFile(file: JSONFileCredential): JSONFileReader = JSONFileReader(file, home, environment)

    /** The `sqlite` fetch, through the same read-only query as the `sqlite` lookup. */
    fun sqliteFetcher(call: SQLiteCall): SQLiteFetcher = SQLiteFetcher(call, database, home, environment)

    companion object {
        /** The outer lookup without its refresh, and the refresher for it — null when it has none. */
        fun split(lookup: CredentialLookup): Pair<CredentialLookup, CredentialRefresh?> =
            if (lookup is CredentialLookup.Refreshing) lookup.base to lookup.refresh else lookup to null

        fun refresher(
            refresh: CredentialRefresh,
            network: NetworkClient,
            /** The executor a CLI call runs on. */
            makeExecutor: (CLICall) -> CLIExecutor,
            now: () -> Double,
            dedicatedDirectory: String? = null,
        ): CredentialRefreshing = when (refresh) {
            is CredentialRefresh.OAuth2 -> OAuth2Refresher(refresh.refresh, network, now)
            is CredentialRefresh.Cli -> CLIRefresher(refresh.call, makeExecutor(refresh.call), dedicatedDirectory)
        }
    }
}
