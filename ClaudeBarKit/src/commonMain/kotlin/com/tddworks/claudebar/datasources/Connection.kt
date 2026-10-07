package com.tddworks.claudebar.datasources

import com.tddworks.claudebar.datasources.lookup.CredentialLookup
import com.tddworks.claudebar.datasources.lookup.CredentialRefresh
import com.tddworks.claudebar.datasources.process.LocalServerFetcher

// What a fetch says about itself — *Import*'s "sends your key to" and "runs", and *CLI location*.
// Each case answers for its own payload, so nothing outside this file switches over the cases
// but the factory.

/** Every URL a request may go to, as written — `{{setting.x}}` and `{{token}}` left for the caller. */
internal val Fetch.urls: List<String>
    get() = when (this) {
        is Fetch.Http -> listOf(request.url)
        is Fetch.HttpSteps -> steps.steps.map { it.request.url }
        // Only this Mac's loopback address, on whatever port the app listens.
        is Fetch.LocalServer -> call.paths.map { "https://127.0.0.1:{{port}}$it" }
        // The cloud's own API, signed with the person's profile — no key of ours.
        is Fetch.CloudWatch, is Fetch.JsonRpc, is Fetch.Cli, is Fetch.Command, is Fetch.File,
        is Fetch.Directory, is Fetch.Sqlite, is Fetch.Script -> emptyList()
    }

/** Every command it may run, as argv. */
internal val Fetch.commands: List<List<String>>
    get() = when (this) {
        is Fetch.JsonRpc -> listOf(listOf(call.cli) + call.args)
        is Fetch.Cli -> listOf(listOf(call.cli) + call.args)
        is Fetch.Command -> listOf(listOf(call.cli) + call.args)
        is Fetch.LocalServer -> listOf(
            LocalServerFetcher.processQuery(call.process),
            listOf("/usr/sbin/lsof", "-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p", "{{pid}}"),
        )
        // The person's own script — *Import* shows it before anything runs.
        is Fetch.Script -> listOf(listOf("/bin/sh", "-c", call.run))
        is Fetch.Http, is Fetch.HttpSteps, is Fetch.File, is Fetch.Directory, is Fetch.Sqlite, is Fetch.CloudWatch -> emptyList()
    }

/** The same fetch with the CLI at [binary] wherever it ran [cli] — *CLI location* (#210). */
internal fun Fetch.runningCLI(cli: String, binary: String): Fetch = when {
    this is Fetch.JsonRpc && call.cli == cli -> Fetch.JsonRpc(call.copy(cli = binary))
    this is Fetch.Cli && call.cli == cli -> Fetch.Cli(call.copy(cli = binary))
    this is Fetch.Command && call.cli == cli -> Fetch.Command(call.copy(cli = binary))
    else -> this
}

/** A credential refresh that runs [cli] repointed at [binary], through the lookups that wrap it. */
internal fun CredentialLookup.runningCLI(cli: String, binary: String): CredentialLookup = when (this) {
    is CredentialLookup.FirstOf -> CredentialLookup.FirstOf(lookups.map { it.runningCLI(cli, binary) })
    is CredentialLookup.Refined -> CredentialLookup.Refined(base.runningCLI(cli, binary), refinement)
    is CredentialLookup.Refreshing -> {
        val refresh = refresh
        CredentialLookup.Refreshing(
            base.runningCLI(cli, binary),
            if (refresh is CredentialRefresh.Cli && refresh.call.cli == cli) CredentialRefresh.Cli(refresh.call.copy(cli = binary)) else refresh,
        )
    }
    else -> this
}
