package com.tddworks.claudebar.datasources.process

import kotlinx.atomicfu.locks.SynchronizedObject
import kotlinx.atomicfu.locks.synchronized
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.IO
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Environment variables as the person's shell sees them — the `loginShell` a lookup that says
 * `"loginShell": true` asks. An app started from Finder, the Dock or Login Items doesn't inherit
 * what `~/.zshrc` exports, so a variable missing from the app's own environment is read from
 * the login shell (#170). A value found there is kept for the session; a miss is asked again,
 * so a key exported later is found without a restart.
 *
 * The lookup blocks its caller for up to the shell's timeout, so give it only to a credential
 * lookup that reaches the environment last.
 */
internal class ShellEnvironment(
    /** The app's own environment. */
    private val process: Map<String, String>,
    private val shell: LoginShellEnvironment,
) {
    private val lock = SynchronizedObject()
    private val found = mutableMapOf<String, String>()

    fun value(name: String): String? {
        process[name]?.takeIf { it.isNotEmpty() }?.let { return it }
        synchronized(lock) { found[name] }?.let { return it }
        // The shell has its own 10-second timeout; this only guards a lookup that never gets a thread.
        val value = runBlocking(Dispatchers.IO) { withTimeoutOrNull(15_000) { shell.value(name) } } ?: return null
        synchronized(lock) { found[name] = value }
        return value
    }
}
