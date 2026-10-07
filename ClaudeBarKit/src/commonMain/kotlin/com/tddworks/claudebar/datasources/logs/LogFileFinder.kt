package com.tddworks.claudebar.datasources.logs

import com.tddworks.claudebar.datasources.modifiedSeconds
import kotlinx.io.files.Path
import kotlinx.io.files.SystemFileSystem

/**
 * The files a `files` glob names, changed since a time: `**` matches any depth, `*` and `?`
 * stay within one name. Hidden files are skipped, symlinked folders aren't followed, and the
 * result is in path order so the same logs always read the same way.
 */
internal object LogFileFinder {
    fun files(pattern: String, changedSinceSeconds: Double): List<String> {
        val (root, rest) = split(pattern)
        if (rest.isEmpty()) return if (isRecent(root, changedSinceSeconds)) listOf(root) else emptyList()
        val matcher = runCatching { Regex("^" + regex(rest) + "$") }.getOrNull() ?: return emptyList()
        val resolvedRoot = runCatching { SystemFileSystem.resolve(Path(root)).toString() }.getOrNull() ?: return emptyList()
        if (SystemFileSystem.metadataOrNull(Path(resolvedRoot))?.isDirectory != true) return emptyList()

        val prefix = if (resolvedRoot.endsWith("/")) resolvedRoot else "$resolvedRoot/"
        val files = mutableListOf<String>()
        val folders = ArrayDeque(listOf(resolvedRoot))
        while (folders.isNotEmpty()) {
            val folder = folders.removeFirst()
            val entries = runCatching { SystemFileSystem.list(Path(folder)) }.getOrDefault(emptyList())
            for (entry in entries) {
                if (entry.name.startsWith(".")) continue
                val path = entry.toString()
                val resolved = runCatching { SystemFileSystem.resolve(entry).toString() }.getOrNull() ?: continue
                val isLink = resolved != path
                val metadata = SystemFileSystem.metadataOrNull(entry) ?: continue
                if (metadata.isDirectory) {
                    if (!isLink) folders += path
                    continue
                }
                if (!resolved.startsWith(prefix)) continue
                if (matcher.matches(resolved.removePrefix(prefix)) && isRecent(path, changedSinceSeconds)) files += path
            }
        }
        return files.sorted()
    }

    /** The folder before the first wildcard, and the pattern after it. */
    fun split(pattern: String): Pair<String, String> {
        val components = pattern.split('/')
        val firstWild = components.indexOfFirst { component -> component.any { it in "*?[" } }
        if (firstWild < 0) return pattern to ""
        val root = components.subList(0, firstWild).joinToString("/")
        return root.ifEmpty { "/" } to components.subList(firstWild, components.size).joinToString("/")
    }

    fun regex(glob: String): String {
        val result = StringBuilder()
        var index = 0
        while (index < glob.length) {
            val character = glob[index]
            if (character == '*' && glob.getOrNull(index + 1) == '*') {
                if (glob.getOrNull(index + 2) == '/') {
                    result.append("(?:[^/]+/)*")
                    index += 3
                } else {
                    result.append(".*")
                    index += 2
                }
                continue
            }
            when (character) {
                '*' -> result.append("[^/]*")
                '?' -> result.append("[^/]")
                else -> {
                    if (character in "\\^$.|?*+()[]{}") result.append('\\')
                    result.append(character)
                }
            }
            index++
        }
        return result.toString()
    }

    private fun isRecent(path: String, sinceSeconds: Double): Boolean {
        if (SystemFileSystem.metadataOrNull(Path(path))?.isRegularFile != true) return false
        val modified = modifiedSeconds(path) ?: return false
        return modified >= sinceSeconds
    }
}
