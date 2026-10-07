package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.DefinitionError
import com.tddworks.claudebar.datasources.double
import com.tddworks.claudebar.datasources.requireString
import com.tddworks.claudebar.datasources.strings
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * *Sign in with browser* as data: the vendor's own login command, and the variable that points
 * it at a folder of its own — `{ "cli": "…", "args": ["login"], "homeVariable": "…_HOME" }`.
 * Swift keeps it beside `AccountSignIn` in DataSources; it is here, as the definition's part,
 * until that worker is ported.
 */
internal data class SignInCall(
    val cli: String,
    val args: List<String>,
    /** Set to the new folder, so the login lands there and nowhere else. */
    val homeVariable: String,
    /** Inherited variables that would pick another way to sign in — a key in the person's shell must not decide which account this becomes. */
    val unset: List<String> = emptyList(),
    /** Seconds to wait for the person to finish in the browser. */
    val timeout: Double = 300.0,
) {
    fun toJson(): JsonObject = JsonObject(mapOf(
        "cli" to JsonPrimitive(cli),
        "args" to JsonArray(args.map(::JsonPrimitive)),
        "homeVariable" to JsonPrimitive(homeVariable),
        "unset" to JsonArray(unset.map(::JsonPrimitive)),
        "timeout" to JsonPrimitive(timeout),
    ))

    companion object {
        fun from(json: JsonElement): SignInCall {
            val o = json as? JsonObject ?: throw DefinitionError("accounts.signIn is an object")
            return SignInCall(
                cli = o.requireString("cli", "accounts.signIn"),
                args = o.strings("args") ?: throw DefinitionError("accounts.signIn needs \"args\""),
                homeVariable = o.requireString("homeVariable", "accounts.signIn"),
                unset = o.strings("unset") ?: emptyList(),
                timeout = o.double("timeout") ?: 300.0,
            )
        }
    }
}
