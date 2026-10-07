package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.DataSources
import com.tddworks.claudebar.datasources.LoginFolders
import com.tddworks.claudebar.datasources.SecretVault
import com.tddworks.claudebar.datasources.process.AccountSignIn

/**
 * Everything that touches this Mac, built once by the composition root and the same for every
 * provider (TARGET_ARCHITECTURE §10). A definition uses only what its cases ask for: the
 * [connections] make each data source with the one connection its fetch needs (the cloud's
 * ports included), and a definition that declares `guestPasses` gets them run. Nothing here
 * names a provider.
 */
internal class Engine(
    val settings: MultiAccountSettingsRepository,
    /** The connections every data source is made over — `systemDataSources()` on the Mac. */
    val connections: DataSources,
    /** The home folder: a usage log's `~`, the signed-in folders and the kept days live under it. */
    val home: String,
    /** The app's environment, which a usage log's `${VAR:-default}` reads. */
    val environment: (String) -> String?,
    /** The folders added logins live in. */
    val folders: LoginFolders,
    /** What a path setting asks of this Mac. */
    val paths: PathChecking,
    /** Whether a path is a program — *CLI location*. */
    val isExecutable: (String) -> Boolean,
    /** A CLI on the PATH, by name. */
    val locate: (String) -> String?,
    val vault: SecretVault? = null,
    /** Where *In use* is recorded; without it no product offers it. */
    val loginsInUse: LoginsInUse? = null,
    /** *Sign in with browser*'s runner. */
    val signIn: AccountSignIn? = null,
    /** Where closed days are kept; without it every read goes to the logs. */
    val ledger: LedgerStore? = null,
    /**
     * The runner for the guest-passes capability, at the declaring definition's CLI location
     * (read each time, so a change applies at once).
     */
    val guestPasses: ((cli: () -> String) -> GuestPassSource)? = null,
    /** Now, in Unix seconds — a usage log's today. */
    val now: () -> Double,
)
