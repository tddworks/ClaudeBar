package com.tddworks.claudebar.providers

import com.tddworks.claudebar.diagnostics.AppLog
import com.tddworks.claudebar.quotas.QuotaStatus
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.atomicfu.locks.SynchronizedObject
import kotlinx.atomicfu.locks.synchronized
import kotlinx.coroutines.flow.StateFlow

/**
 * *In use* — which of a product's logins new terminal sessions start with. Only a product
 * whose CLI can be started on a login's folder has one (`Provider.inUse`). The choice is
 * recorded as that folder, through [LoginsInUse], under the CLI's name — the shell starts a
 * CLI, not a product, so two products on one CLI share its record and the last choice wins.
 * Running sessions keep theirs.
 */
internal class InUse internal constructor(
    /** Its product's logins — below it; never the product itself (TARGET §2.1). */
    private val accounts: Accounts,
    private val productId: String,
    private val productName: String,
    /** The command new sessions run, and the variable that points it at a folder. */
    val command: TerminalCommand,
    private val record: LoginsInUse,
    /** *Switch when low* — the opt-in policy [review] asks. */
    val switchWhenLow: SwitchWhenLow,
) {
    /** The login new sessions start with, by id. A record naming a folder no login has is the plain login. */
    private val loginId = ObservableState(
        record.folder(command.name)?.let { folder -> accounts.firstOrNull { it.folder?.path == folder }?.id } ?: accounts.plain.id,
    )

    /** The suggestion already told — `<in use>><suggested>` — so a low is told once. */
    private val toldLock = SynchronizedObject()
    private var told: String? = null

    /** Bumped when another login is put in use. */
    val revision: StateFlow<Long> get() = loginId.revision

    /** The login new sessions start with — the plain login until another is chosen. */
    val login: Account get() = accounts.firstOrNull { it.id == loginId.current } ?: accounts.plain

    /** The logins new sessions can start on: the plain login and every folder login. */
    val logins: List<Account> get() = accounts.filter { it.isDefault || it.folder != null }

    /** Whether there is a choice to offer: more than one login to start on. */
    val offersChoice: Boolean get() = logins.size > 1

    /** Whether [account] is the login new sessions start with — only when there is a choice. */
    fun isInUse(account: Account): Boolean = canBeInUse(account) && login === account

    /** Whether [account] can be chosen for new sessions: there is a choice, and it is one of the logins offered. */
    fun canBeInUse(account: Account): Boolean = offersChoice && logins.any { it === account }

    /** *Use for new sessions* — records [account]'s folder, nothing for the plain login. */
    fun use(account: Account): Outcome<Unit> = outcome { choose(account) }

    /** The removed login was in use: new sessions go back to the plain login. */
    internal fun forget(account: Account) {
        if (loginId.current != account.id) return
        runCatching { record.use(null, command.name) }
        loginId.update { accounts.plain.id }
    }

    /** The login worth moving to: the one in use is critical or out, and another enabled login has more left — the most. */
    val worthSwitchingTo: Account?
        get() {
            val current = login
            val left = current.percentLeft
            if (current.status < QuotaStatus.CRITICAL || left == null) return null
            return logins.filter { it !== current && it.isEnabled && (it.percentLeft ?: -1.0) > left }
                .maxByOrNull { it.percentLeft ?: -1.0 }
        }

    /**
     * What to tell the person after a refresh: that *Switch when low* moved new sessions, or —
     * once per low — which login is worth moving to. Throws when the record can't be written;
     * the monitor calls it, never a page.
     */
    fun review(): InUseNotice? {
        val current = login
        val next = switchWhenLow.next(current, logins)
        if (next != null) {
            choose(next)
            synchronized(toldLock) { told = null }
            return InUseNotice.Switched(current, next)
        }
        val better = worthSwitchingTo
        if (better == null) {
            synchronized(toldLock) { told = null }
            return null
        }
        val pair = "${current.id}>${better.id}"
        val first = synchronized(toldLock) { (told != pair).also { told = pair } }
        return if (first) InUseNotice.WorthSwitching(current, better) else null
    }

    private fun choose(account: Account) {
        if (logins.none { it === account }) {
            throw UsageError.ExecutionFailed("This login can't be used for new $productName sessions.")
        }
        record.use(if (account.isDefault) null else account.folder?.path, command.name)
        loginId.update { account.id }
        AppLog.providers.info("$productId: new sessions use ${if (account.isDefault) "the plain login" else "an added login"}")
    }
}

/** The command new terminal sessions run, and the variable that starts it on a login's folder: `claude` with `CLAUDE_CONFIG_DIR`. */
internal data class TerminalCommand(
    /** The CLI — and the name its choice is recorded under. */
    val name: String,
    val variable: String,
)

/** What *In use* has to tell the person after a refresh. Logins compare as themselves. */
internal sealed class InUseNotice {
    abstract val from: Account
    abstract val to: Account

    /** *Switch when low* moved new sessions from one login to another. */
    data class Switched(override val from: Account, override val to: Account) : InUseNotice()

    /** The login in use is low and [to] has more left. */
    data class WorthSwitching(override val from: Account, override val to: Account) : InUseNotice()
}
