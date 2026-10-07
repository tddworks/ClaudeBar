package com.tddworks.claudebar.datasources

import com.tddworks.claudebar.datasources.fetch.aws.AWSClients
import com.tddworks.claudebar.datasources.fetch.insecureLocalhostNetworkClient
import com.tddworks.claudebar.datasources.fetch.systemNetworkClient
import com.tddworks.claudebar.datasources.lookup.SystemLookup
import com.tddworks.claudebar.datasources.mapping.JavaScriptCoreEngine
import com.tddworks.claudebar.datasources.process.CLIFetcher
import com.tddworks.claudebar.datasources.process.CommandFetcher
import com.tddworks.claudebar.datasources.process.LoginShellEnvironment
import com.tddworks.claudebar.datasources.process.MacProcesses
import com.tddworks.claudebar.datasources.process.PipeCLIExecutor
import kotlinx.coroutines.runBlocking
import platform.Foundation.NSDate
import platform.Foundation.NSHomeDirectory
import platform.Foundation.timeIntervalSince1970

/** Data sources on the real network, CLIs, Keychain, browsers and file system of this Mac. */
internal fun systemDataSources(
    home: String = NSHomeDirectory(),
    now: () -> Double = { NSDate().timeIntervalSince1970 },
): DataSources {
    val host = MacProcesses.host
    val environment: (String) -> String? = { host.machine.environment[it] }
    val network = systemNetworkClient()
    val shell = LoginShellEnvironment(PipeCLIExecutor(host), { host.machine.environment })
    return DataSources(
        home = home,
        environment = environment,
        network = network,
        loopback = insecureLocalhostNetworkClient(),
        makeCLIExecutor = CLIFetcher.system(host),
        makeCommandExecutor = CommandFetcher.system(host),
        transports = MacProcesses.transports,
        directory = host::directory,
        processEnvironment = { host.machine.environment },
        files = host.files,
        processPaths = host.runningProcesses::executablePaths,
        security = SystemLookup.security,
        database = SystemLookup.database,
        browserCookies = SystemLookup.browserCookies(home),
        browserStorage = SystemLookup.browserStorage(home),
        // Credential lookups are synchronous, as the Swift ones were: a lookup that asks the
        // login shell waits for it (`"environment": { …, "loginShell": true }` only).
        loginShell = { name -> runBlocking { shell.value(name) } },
        cloudWatch = AWSClients.cloudWatch(network, home, environment, now),
        priceCatalog = AWSClients.priceCatalog(network, home, environment, now),
        scriptEngine = JavaScriptCoreEngine(),
        now = now,
    )
}
