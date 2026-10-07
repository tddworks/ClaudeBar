package com.tddworks.claudebar.activity

import com.tddworks.claudebar.providers.Account
import com.tddworks.claudebar.providers.ObservableState
import com.tddworks.claudebar.providers.Outcome
import com.tddworks.claudebar.providers.Provider
import kotlinx.coroutines.flow.StateFlow

/** The shell the lines are written for. */
public enum class LoginShell(val tag: String) {
    ZSH("zsh"),
    BASH("bash"),
    FISH("fish"),
    ;

    companion object {
        /** The person's login shell, from `$SHELL` — zsh, macOS's own, when unknown. */
        fun login(path: String?): LoginShell {
            val name = path?.trimEnd('/')?.substringAfterLast('/').orEmpty()
            return entries.firstOrNull { it.tag == name } ?: ZSH
        }
    }
}

/**
 * The lines in the person's shell that start each CLI on the login in use — what
 * [NewSessions] needs from the disk.
 */
internal interface ShellLines {
    /** The lines as they would be written for [shell]. */
    fun lines(shell: LoginShell): String

    /** The file they go in. */
    fun file(shell: LoginShell): String

    fun isInstalled(shell: LoginShell): Boolean

    /** Throws when the file can't be written. */
    fun install(shell: LoginShell)

    /** Throws when the file can't be changed. */
    fun remove(shell: LoginShell)
}

/**
 * *New terminal sessions* — which login each CLI starts with, and the shell lines that make the
 * choice count. A login chosen before the lines are in the shell waits for them, so a switch
 * never silently does nothing; the plain login needs no lines and is never kept waiting.
 */
public class NewSessions internal constructor(
    products: List<Provider>,
    private val shellLines: ShellLines,
    private val announcer: InUseAnnouncer? = null,
    shell: LoginShell,
) {
    private data class Seen(val shell: LoginShell, val isSetUp: Boolean, val waiting: Account? = null, val problem: String? = null)

    /** The products whose new sessions can be chosen — those with `inUse`. */
    val products: List<Provider> = products.filter { it.inUse != null }

    private val state = ObservableState(Seen(shell, shellLines.isInstalled(shell)))

    /** Bumped after every change. */
    val revision: StateFlow<Long> get() = state.revision

    /** The shell the lines are for — the login shell until the person picks another. */
    var shell: LoginShell
        get() = state.current.shell
        set(value) {
            state.update { it.copy(shell = value, isSetUp = shellLines.isInstalled(value)) }
        }

    /** Whether the lines are in [shell]'s file. */
    val isSetUp: Boolean get() = state.current.isSetUp

    /** The login chosen before the lines were there. */
    val waiting: Account? get() = state.current.waiting

    /** What went wrong last, in the person's words. */
    val problem: String? get() = state.current.problem

    /** What a product's strip shows. Logins compare as themselves. */
    sealed class State {
        data object WaitingForSetup : State()

        data class WorthSwitching(val from: Account, val to: Account) : State()

        /** The login in use. */
        data class Using(val login: Account) : State()
    }

    /**
     * What a product's strip shows: the setup a choice waits for, the login worth moving to,
     * or the login in use. Null when there is no choice to offer.
     */
    fun state(product: Provider): State? {
        val inUse = product.inUse ?: return null
        if (!inUse.offersChoice) return null
        if (isWaiting(product)) return State.WaitingForSetup
        inUse.worthSwitchingTo?.let { return State.WorthSwitching(inUse.login, it) }
        return State.Using(inUse.login)
    }

    /** The CLIs the lines wrap — `claude`, `codex` — each once, however many products run it. */
    val commands: List<String> get() = products.mapNotNull { it.inUse?.command?.name }.distinct()

    /** The lines as the setup shows them. */
    val lines: String get() = shellLines.lines(shell)

    /** The file they go in. */
    val file: String get() = shellLines.file(shell)

    /** The product [providerId] names, when its new sessions can be chosen. */
    fun product(providerId: String): Provider? = products.firstOrNull { it.id == providerId }

    /** Whether a choice for [product] waits for the setup. */
    fun isWaiting(product: Provider): Boolean = waiting?.providerId == product.id

    /** Whether a choice for this login's product waits for the setup. */
    fun isWaiting(login: Account): Boolean = waiting?.providerId == login.providerId

    /** *Use for new sessions* — at once when the lines are there (or for the plain login), else once they are set up. */
    fun use(account: Account) {
        val installed = shellLines.isInstalled(shell)
        state.update { it.copy(isSetUp = installed) }
        if (!installed && !account.isDefault) {
            state.update { it.copy(waiting = account) }
            return
        }
        apply(account)
    }

    /** What `claudebar://use?provider=…&account=…` did. */
    enum class LinkOutcome {
        USED,
        WAITING_FOR_SETUP,

        /** No such product, or no such login that new sessions can start on. */
        UNKNOWN,
    }

    /** `claudebar://use` — the login a link names, by its product's id and its name. */
    fun use(providerId: String, name: String): LinkOutcome {
        val product = product(providerId) ?: return LinkOutcome.UNKNOWN
        val account = product.accounts.named(name) ?: return LinkOutcome.UNKNOWN
        if (product.inUse?.canBeInUse(account) != true) return LinkOutcome.UNKNOWN
        use(account)
        return if (isWaiting(product)) LinkOutcome.WAITING_FOR_SETUP else LinkOutcome.USED
    }

    /** After a login's refresh: *Switch when low* moves new sessions, or a login worth moving to is announced — once per low. */
    suspend fun review(refreshed: Account) {
        val product = product(refreshed.providerId) ?: return
        val inUse = product.inUse ?: return
        val notice = runCatching { inUse.review() }.getOrNull() ?: return
        announcer?.announce(InUseAlert(notice, product))
    }

    /** *Add to ~/.zshrc* — writes the lines, then makes the waiting choice. */
    fun setUp() {
        try {
            shellLines.install(shell)
        } catch (failure: Exception) {
            state.update { it.copy(problem = "ClaudeBar couldn't write $file: ${failure.message}") }
            return
        }
        state.update { it.copy(isSetUp = true) }
        waiting?.let(::apply)
        state.update { it.copy(waiting = null) }
    }

    /** *Copy — I'll add it* — the person adds the lines; the choice is made now. Returns the lines to copy. */
    fun setUpByHand(): String {
        waiting?.let(::apply)
        state.update { it.copy(waiting = null) }
        return lines
    }

    fun cancel() {
        state.update { it.copy(waiting = null) }
    }

    /** *Remove* — takes the lines out, and every CLI goes back to its plain login. */
    fun turnOff() {
        try {
            shellLines.remove(shell)
        } catch (failure: Exception) {
            state.update { it.copy(problem = "ClaudeBar couldn't change $file: ${failure.message}") }
            return
        }
        state.update { it.copy(isSetUp = false) }
        for (product in products) product.inUse?.use(product.defaultAccount)
    }

    private fun apply(account: Account) {
        val inUse = product(account.providerId)?.inUse
        val problem = when (val outcome = inUse?.use(account)) {
            null -> "This login's product can't choose a login for new sessions."
            is Outcome.Done -> null
            is Outcome.Refused -> outcome.reason
        }
        state.update { it.copy(problem = problem) }
    }
}
