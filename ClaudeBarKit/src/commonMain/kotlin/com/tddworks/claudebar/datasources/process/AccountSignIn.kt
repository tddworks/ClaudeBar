package com.tddworks.claudebar.datasources.process

import com.tddworks.claudebar.datasources.DefinitionJson
import com.tddworks.claudebar.datasources.LoginFolders
import com.tddworks.claudebar.datasources.SignInProcess
import com.tddworks.claudebar.datasources.decoding
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.decodeFromJsonElement

/**
 * *Sign in with browser* as data: the vendor's own login command, and the variable that
 * points it at a folder of its own —
 * `{ "cli": "…", "args": ["login"], "homeVariable": "…_HOME", "unset": ["…_API_KEY"] }`.
 */
@Serializable
internal data class SignInCall(
    val cli: String,
    val args: List<String>,
    /** Set to the new folder, so the login lands there and nowhere else. */
    val homeVariable: String,
    /** Inherited variables that would pick another way in: a key in the shell must not decide the account. */
    val unset: List<String> = emptyList(),
    /** Seconds to wait for the person to finish in the browser. */
    val timeout: Double = 300.0,
) {
    companion object {
        fun from(json: JsonElement): SignInCall = decoding("signIn") { DefinitionJson.decodeFromJsonElement(json) }
    }
}

/** Why a sign-in did not give a login — each says what to do next. */
internal sealed class SignInError(message: String) : Exception(message) {
    data class CliNotFound(val cli: String) :
        SignInError("`$cli` wasn't found. Install it, or choose a folder you already signed in to.")

    data object FolderExists : SignInError("That folder already exists, so ClaudeBar won't sign in there. Try again.")

    data object DidNotFinish : SignInError("Sign-in didn't finish. Try again and complete it in your browser.")

    data object TimedOut : SignInError("Sign-in timed out. Try again and complete it in your browser within five minutes.")
}

/**
 * Signs in to a vendor's CLI into a NEW folder ClaudeBar makes (0700). The folder is the
 * whole result: whoever checks it next decides whether it holds a login. Nothing is left
 * behind when the login does not finish.
 */
internal class AccountSignIn(
    private val process: SignInProcess,
    private val folders: LoginFolders,
    /** The CLI a call names — a name on the PATH, or the path its provider's CLI location gave it. */
    private val locate: (String) -> String?,
    private val environment: () -> Map<String, String>,
) {
    suspend fun signIn(call: SignInCall, into: String) {
        val executable = locate(call.cli) ?: throw SignInError.CliNotFound(call.cli)
        if (folders.exists(into)) throw SignInError.FolderExists
        folders.create(into)
        try {
            run(call, executable, into)
        } catch (failed: Throwable) {
            folders.delete(into)
            throw failed
        }
    }

    /** Signs in again where a login already lives — its session expired. The folder is kept whatever happens. */
    suspend fun signInAgain(call: SignInCall, folder: String) {
        val executable = locate(call.cli) ?: throw SignInError.CliNotFound(call.cli)
        if (!folders.exists(folder)) throw SignInError.DidNotFinish
        run(call, executable, folder)
    }

    /** The login, pointed at [folder], with nothing inherited that would pick another way in. */
    private suspend fun run(call: SignInCall, executable: String, folder: String) {
        val variables = environment().toMutableMap()
        call.unset.forEach(variables::remove)
        variables[call.homeVariable] = folder
        val status = process.run(executable, call.args, variables, folder, call.timeout)
        if (status != 0) throw SignInError.DidNotFinish
    }
}
