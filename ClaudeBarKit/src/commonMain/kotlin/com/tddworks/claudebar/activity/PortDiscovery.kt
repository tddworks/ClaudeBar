package com.tddworks.claudebar.activity

import kotlinx.io.buffered
import kotlinx.io.files.Path
import kotlinx.io.files.SystemFileSystem
import kotlinx.io.readString
import kotlinx.io.writeString

/** The file the installed hook reads ClaudeBar's port from: `~/.claude/claudebar-hook-port`. */
internal class PortDiscovery(val portFilePath: String) {
    private val file = Path(portFilePath)

    /** Leaves [port] for the hook, creating the folder if needed. */
    fun writePort(port: Int) {
        file.parent?.let { SystemFileSystem.createDirectories(it) }
        val temporary = Path("$portFilePath.writing")
        SystemFileSystem.sink(temporary).buffered().use { it.writeString("$port") }
        SystemFileSystem.atomicMove(temporary, file)
    }

    /** The port left, or null when there is no file or it holds no number. */
    fun readPort(): Int? = runCatching {
        SystemFileSystem.source(file).buffered().use { it.readString() }
    }.getOrNull()?.trim()?.toIntOrNull()

    fun removePortFile() {
        runCatching { SystemFileSystem.delete(file, mustExist = false) }
    }

    companion object {
        /** The file under [home], where the installed hook looks. */
        fun inHome(home: String): PortDiscovery = PortDiscovery("${home.trimEnd('/')}/.claude/claudebar-hook-port")
    }
}
