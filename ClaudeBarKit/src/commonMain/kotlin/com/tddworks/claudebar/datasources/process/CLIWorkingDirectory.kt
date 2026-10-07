package com.tddworks.claudebar.datasources.process

/**
 * The dedicated folder every CLI fetch runs in. A CLI that gates on folder trust (#44, #267)
 * prompts before anything interactive; one that inherits the app's working directory —
 * usually `/` from Finder or at login — stalls on that prompt. Trusted once here, it never
 * blocks a refresh.
 */
internal object CLIWorkingDirectory {
    /** `Application Support/ClaudeBar/Probe`, made when missing. The name stays: CLIs already trust it. */
    fun resolve(machine: Machine, files: MachineFiles): String {
        val folder = machine.applicationSupportDirectory.trimEnd('/') + "/ClaudeBar/Probe"
        runCatching { files.makeDirectories(folder) }
        return folder
    }
}
