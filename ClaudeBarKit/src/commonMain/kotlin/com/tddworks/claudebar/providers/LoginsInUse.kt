package com.tddworks.claudebar.providers

import kotlinx.io.buffered
import kotlinx.io.files.Path
import kotlinx.io.files.SystemFileSystem
import kotlinx.io.readString
import kotlinx.io.writeString

/**
 * *In use* — which login new terminal sessions of a CLI start with: one file per CLI,
 * `~/.claudebar/in-use/<command>`, holding the login's folder. Empty, or no file, is the plain
 * login the CLI already uses. The shell lines `ShellSetup` writes read it on every `claude` or
 * `codex`, so the file is the only record: nothing else keeps a copy.
 */
internal interface LoginsInUse {
    /** The folder new sessions of [command] start with — null for the plain login. */
    fun folder(command: String): String?

    /** Saves it; null goes back to the plain login. */
    fun use(folder: String?, command: String)
}

/** The real files, under `~/.claudebar/in-use`. */
internal class DiskLoginsInUse(val root: String) : LoginsInUse {
    override fun folder(command: String): String? {
        val text = runCatching { SystemFileSystem.source(Path(file(command))).buffered().use { it.readString() } }.getOrNull() ?: return null
        val path = text.trim()
        return if (path.isEmpty()) null else standardized(path)
    }

    override fun use(folder: String?, command: String) {
        SystemFileSystem.createDirectories(Path(root))
        // Written whole and renamed into place, so a shell never reads half a path.
        val file = Path(file(command))
        val writing = Path("$file.writing")
        SystemFileSystem.sink(writing).buffered().use { it.writeString(folder?.let(::standardized) ?: "") }
        SystemFileSystem.atomicMove(writing, file)
    }

    fun file(command: String): String = Path(root, command).toString()

    /** One spelling of a folder — no `.` or `..`, no trailing slash — as a signed-in folder is written. */
    private fun standardized(path: String): String = SignedInFolder(path, AccountOrigin.FOLDER).path

    companion object {
        fun defaultRoot(home: String): String = Path(home, ".claudebar", "in-use").toString()
    }
}
