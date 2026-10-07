package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.DataSourceError
import com.tddworks.claudebar.quotas.QuotaStatus
import com.tddworks.claudebar.quotas.UsageError
import com.tddworks.claudebar.quotas.UsageSnapshot
import kotlinx.coroutines.flow.StateFlow

/**
 * A LOGIN YOU PAY FOR — who it is, its saved values, and what we last saw for it. Two Codex
 * logins are two accounts of one `Provider`: two things to watch (each its own pill and
 * menu-bar entry), one thing to fix.
 *
 * It knows only itself (TARGET §2.1): who it is, its values, its pause, what we last saw, and
 * what its definition alone says. It names its product by id and never refers to it — ask the
 * product about a login (`provider.refresh(account)`, `provider.isInLineup(account)`).
 */
internal class Account internal constructor(
    /** What its product's definition says — data, given at birth. */
    internal val definition: ProviderDefinition,
    /** Where its own pause is kept. */
    private val settings: ProviderSettingsRepository,
    login: ProviderAccount,
    /** Its account settings — the Codex folder, the login's account id. */
    val values: Map<String, String>,
    /** How it was added — null for the default login and for logins saved before it was recorded. */
    val madeBy: AccountOrigin? = null,
    usageHistory: UsageHistory? = null,
    /** *Share Claude Code* — read with the plain login's CLI, so only it has them. */
    val guestPasses: GuestPasses? = null,
) {
    /** Its product, by id — a value, never a reference. */
    val providerId: String = definition.id

    /** `codex` for the default login, `codex.<account>` for an added one — what every saved setting and pin is keyed by. */
    val id: String = login.id
    val isDefault: Boolean = login.isDefault

    /** The login's own id within the provider — `default` for the default login. */
    val accountId: String = login.accountId

    /** What the person gave, or its login file holds. */
    val email: String? = login.email

    private data class Seen(
        val label: String,
        val isEnabled: Boolean,
        val isSyncing: Boolean = false,
        val snapshot: UsageSnapshot? = null,
        val lastError: UsageError? = null,
        val lastFailedStep: DataSourceError.Step? = null,
        val answeredBy: String? = null,
        val usageHistory: UsageHistory?,
    )

    private val state = ObservableState(
        Seen(
            label = login.label,
            isEnabled = if (login.isDefault) settings.isOn(Provider.PLAIN_LOGIN_KEY, definition.id) ?: true
            else settings.isEnabled(login.id, definition.enabledByDefault),
            usageHistory = usageHistory,
        ),
    )

    /** Bumped after every change to what this login shows. */
    val revision: StateFlow<Long> get() = state.revision

    /** The name the person gave it — empty when they gave none. */
    var label: String
        get() = state.current.label
        internal set(value) {
            state.update { it.copy(label = value) }
        }

    /** The login's own *Pause* — never the product's switch. */
    var isEnabled: Boolean
        get() = state.current.isEnabled
        set(value) {
            state.update { it.copy(isEnabled = value) }
            if (isDefault) settings.setOn(value, Provider.PLAIN_LOGIN_KEY, providerId) else settings.setEnabled(value, id)
        }

    // What we last saw

    var isSyncing: Boolean
        get() = state.current.isSyncing
        internal set(value) {
            state.update { it.copy(isSyncing = value) }
        }

    val snapshot: UsageSnapshot? get() = state.current.snapshot

    /** Why the last refresh failed, so every screen that reads one keeps reading one. */
    var lastError: UsageError?
        get() = state.current.lastError
        internal set(value) {
            state.update { it.copy(lastError = value) }
        }

    /** Which step failed last — lookup, fetch or mapping. Null after a success. */
    val lastFailedStep: DataSourceError.Step? get() = state.current.lastFailedStep

    /** The kind of the data source that produced [snapshot] — *via RPC*. */
    val answeredBy: String? get() = state.current.answeredBy

    /** What Settings calls that data source — *RPC*, *API*, *Terminal*. */
    val answeredByLabel: String? get() = answeredBy?.let { definition.dataSource(it)?.label ?: it }

    /**
     * *NOT SET UP* — no usage yet, and the last refresh found no tool on this Mac or no
     * sign-in to read with. Waiting for the person, not failing (#198).
     */
    val needsSetup: Boolean
        get() {
            val seen = state.current
            if (seen.snapshot != null) return false
            return seen.lastError is UsageError.CliNotFound || seen.lastError is UsageError.AuthenticationRequired
        }

    val readsUsage: Boolean get() = usageHistory?.hasUsage == true

    /** QUOTA health — the worst quota in its usage. A failed fetch is not a status: it is [lastError], and the last usage stays. */
    val status: QuotaStatus get() = snapshot?.overallStatus ?: QuotaStatus.HEALTHY

    /** Where the login lives, for a login added by its folder. */
    val folder: SignedInFolder?
        get() {
            if (isDefault) return null
            val rule = definition.accounts?.folder ?: return null
            val path = values[rule.savedAs] ?: return null
            return SignedInFolder(path, madeBy ?: AccountOrigin.FOLDER)
        }

    /** What its tightest quota has left, in percent — null before a usage. */
    val percentLeft: Double? get() = snapshot?.lowestQuota?.percentRemaining

    /** The email the data source reported, else the one it was added with. */
    val accountEmail: String? get() = snapshot?.accountEmail ?: email

    /** What it is called: the name the person gave it, else its login's email, else the product's name. */
    val displayName: String
        get() {
            val given = label.trim()
            if (given.isNotEmpty()) return given
            return accountEmail ?: definition.profile.name
        }

    // What its definition says

    /** Its product's face — symbol, colours — as the definition gives it. */
    val look: ProviderLook get() = definition.profile.look
    val cliCommand: String get() = definition.cli ?: ""
    val statusPageURL: String? get() = definition.profile.links.status

    /**
     * What this login used, day by day, from its own logs — null when the provider offers no
     * usage history, doesn't say where an added login's logs are, or the login was removed.
     */
    var usageHistory: UsageHistory?
        get() = state.current.usageHistory
        internal set(value) {
            state.update { it.copy(usageHistory = value) }
        }

    // Recording a fetch (the provider's)

    internal fun succeed(usage: UsageSnapshot, kind: String): UsageSnapshot {
        state.update { it.copy(snapshot = usage, lastError = null, lastFailedStep = null, answeredBy = kind) }
        return usage
    }

    /**
     * Some of its data sources failed while others answered (`together`): the usage they gave
     * stays, and the failure shows beside it as fetch health — never wiping what was seen.
     */
    internal fun noteFailure(error: Throwable) {
        state.update { it.copy(lastError = error.asUsageError(), lastFailedStep = (error as? DataSourceError)?.step) }
    }

    internal fun fail(error: Throwable) {
        state.update { seen ->
            val reason = error.asUsageError()
            // An added login that is signed out shows nothing rather than its last usage, which would read as still current.
            val signedOut = !isDefault && (reason is UsageError.AuthenticationRequired || reason is UsageError.SessionExpired)
            seen.copy(lastError = reason, lastFailedStep = (error as? DataSourceError)?.step, snapshot = if (signedOut) null else seen.snapshot)
        }
    }

    override fun toString(): String = "Account($id)"
}
