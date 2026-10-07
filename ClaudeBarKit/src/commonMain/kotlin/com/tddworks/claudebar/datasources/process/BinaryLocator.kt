package com.tddworks.claudebar.datasources.process

import com.tddworks.claudebar.diagnostics.AppLog
import kotlinx.atomicfu.locks.SynchronizedObject
import kotlinx.atomicfu.locks.synchronized

/**
 * Finds where a CLI is installed: the person's login shell is asked `which` (its PATH holds
 * nix-darwin, Homebrew, npm …), and when that fails — an app started by launchd — the common
 * install folders are searched.
 *
 * Architecture-aware (#251): an Intel-only binary runs under Rosetta, and macOS then names
 * ClaudeBar, the app that spawned it, in its "apps for Intel processors" warning. So a login
 * shell without a native slice is swapped for the universal `/bin/zsh`, a native copy beats an
 * Intel-only one, and settling on an Intel-only binary is logged, never silent.
 */
internal class BinaryLocator(
    private val machine: Machine,
    private val files: MachineFiles,
    private val processes: Subprocesses,
    now: () -> Double = ::monotonicSeconds,
) {
    /** Resolved paths, misses included, so a missing CLI doesn't spawn a shell every refresh. */
    private val toolCache = SingleFlightCache<String?>(now)
    private val shellPathCache = SingleFlightCache<String>(now)
    private val rosettaNotices = HashSet<String>()
    private val noticesLock = SynchronizedObject()

    /** Where CLIs are installed on a Mac, searched when the shell can't answer. */
    val commonPaths: List<String>
        get() {
            val home = machine.homeDirectory
            return listOf(
                "$home/.local/bin",
                "$home/.cargo/bin",
                "$home/.bun/bin",
                "$home/bin",
                "/opt/homebrew/bin",
                "/usr/local/bin",
                "$home/.nix-profile/bin",
                "/run/current-system/sw/bin",
                "/nix/var/nix/profiles/default/bin",
                "$home/.npm-global/bin",
                "/usr/local/lib/node_modules/.bin",
                "$home/Library/pnpm",
                "$home/.nvm/versions",
                "$home/Library/Application Support/Herd/config/nvm/versions",
            )
        }

    fun locate(tool: String): String? = which(tool)

    /** Forgets every lookup — wired to a manual refresh, when the person may just have installed a tool. */
    fun invalidateCaches() {
        toolCache.invalidateAll()
        shellPathCache.invalidateAll()
        AppLog.probes.debug("BinaryLocator: caches invalidated")
    }

    /**
     * The tool's full path, or null. A cached path that no longer runs (an upgrade moved
     * nvm's folder, an uninstall) is looked up again rather than handed back.
     */
    fun which(tool: String): String? {
        val cached = cachedResolve(tool)
        if (cached != null && !files.isExecutable(cached)) {
            AppLog.probes.debug("BinaryLocator: cached path for '$tool' is stale, re-resolving")
            toolCache.invalidate(tool)
            return cachedResolve(tool)
        }
        return cached
    }

    private fun cachedResolve(tool: String): String? =
        toolCache.value(tool, ttl = { if (it == null) NOT_FOUND_TTL else FOUND_TTL }) { resolve(tool) }

    private fun resolve(tool: String): String? {
        // A full path needs no lookup, and the shell guard would reject its '/'.
        if ('/' in tool && files.isExecutable(tool)) return tool
        whichViaShell(tool)?.let { return settled(tool, it, candidates(commonPaths, tool)) }
        val path = findInCommonPaths(tool) ?: return null
        noteRosettaCost(tool, path)
        return path
    }

    /**
     * The shell's answer, unless this Mac can't run it natively and a fallback folder holds a
     * native copy. No architecture information is no reason to override it.
     */
    fun settled(tool: String, shellAnswer: String, fallbackCandidates: List<String>): String {
        val native = machine.architecture
        val slices = MachOSliceReader.architectures(shellAnswer, files)
        if (slices == null || native in slices) return shellAnswer
        val copy = fallbackCandidates.firstOrNull { MachOSliceReader.architectures(it, files)?.contains(native) == true }
        if (copy == null) {
            noteRosettaCost(tool, shellAnswer)
            return shellAnswer
        }
        AppLog.probes.info("BinaryLocator: '$tool' resolved to $shellAnswer, which has no ${native.name.lowercase()} slice; using the native copy at $copy instead")
        return copy
    }

    /** The shell binary the lookups spawn: the person's own, unless it has no slice this Mac runs natively. */
    fun whichShellPath(preferred: String): String {
        val chosen = whichShellPath(preferred, machine.architecture, MachOSliceReader.architectures(preferred, files))
        if (chosen != preferred) {
            AppLog.probes.info("BinaryLocator: '$preferred' has no slice this Mac runs natively; using /bin/zsh for PATH lookups so ClaudeBar isn't blamed for Intel apps")
        }
        return chosen
    }

    /** Records once per path that the binary settled on is Intel-only and runs under Rosetta. */
    private fun noteRosettaCost(tool: String, path: String) {
        if (machine.architecture != BinaryArchitecture.ARM64) return
        val slices = MachOSliceReader.architectures(path, files) ?: return
        if (BinaryArchitecture.ARM64 in slices) return
        if (!synchronized(noticesLock) { rosettaNotices.add(path) }) return
        AppLog.probes.info("BinaryLocator: '$tool' at $path is Intel-only and will run under Rosetta; macOS may name ClaudeBar in its 'apps for Intel processors' warning")
    }

    private fun whichViaShell(tool: String): String? {
        val start = monotonicSeconds()
        val preferred = machine.environment["SHELL"] ?: "/bin/zsh"
        val shell = Shell.detect(preferred)
        val result = processes.capture(whichShellPath(preferred), shell.whichArguments(tool))
        val elapsed = (monotonicSeconds() - start).secondsText()
        if (result == null) {
            AppLog.probes.debug("BinaryLocator.whichViaShell('$tool') failed after ${elapsed}s")
            return null
        }
        AppLog.probes.debug("BinaryLocator.whichViaShell('$tool') took ${elapsed}s")
        if (result.exitCode != 0) return null
        return shell.parseWhichOutput(result.standardOutput)
    }

    /** The common folders' copy of a tool — a native one first (#251). */
    fun findInCommonPaths(tool: String): String? = candidates(commonPaths, tool).firstOrNull()

    /** Every install of [tool] under [basePaths], a native one first, otherwise in the order given. */
    fun candidates(basePaths: List<String>, tool: String): List<String> {
        val found = mutableListOf<String>()
        for (base in basePaths) {
            val direct = "$base/$tool"
            if (files.isExecutable(direct)) found += direct
            if ("nvm/versions" in base || "Herd" in base) searchNvmVersions(base, tool)?.let(found::add)
        }
        return nativeFirst(found)
    }

    /** Candidates built for this Mac ahead of the rest; unreadable ones count as neither. */
    fun nativeFirst(paths: List<String>): List<String> {
        val native = machine.architecture
        return paths.withIndex().sortedWith(
            compareByDescending<IndexedValue<String>> { MachOSliceReader.architectures(it.value, files)?.contains(native) ?: false }
                .thenBy { it.index },
        ).map { it.value }
    }

    /** `base/node/vX.Y.Z/bin/tool`: the newest, unless only an older one is native (#251). */
    private fun searchNvmVersions(base: String, tool: String): String? {
        val nodeVersions = if (base.endsWith("/node")) base else "$base/node"
        val versions = files.list(nodeVersions) ?: return null
        val candidates = versions.sortedWith { a, b -> numericCompare(b, a) }
            .map { "$nodeVersions/$it/bin/$tool" }
            .filter(files::isExecutable)
        val path = nativeFirst(candidates).firstOrNull() ?: return null
        AppLog.probes.debug("BinaryLocator.searchNvmVersions('$tool') found at $path")
        return path
    }

    /**
     * The login shell's PATH, cached: it is part of every terminal run's environment, and
     * uncached it would spawn a shell per fetch per provider.
     */
    fun shellPath(): String = shellPathCache.value(SHELL_PATH_KEY, ttl = { SHELL_PATH_TTL }) { computeShellPath() }

    private fun computeShellPath(): String {
        val start = monotonicSeconds()
        val preferred = machine.environment["SHELL"] ?: "/bin/zsh"
        val shell = Shell.detect(preferred)
        val fallback = machine.environment["PATH"] ?: "/usr/bin:/bin"
        val result = processes.capture(whichShellPath(preferred), shell.pathArguments())
        val elapsed = (monotonicSeconds() - start).secondsText()
        if (result == null) {
            AppLog.probes.debug("BinaryLocator.shellPath() failed after ${elapsed}s")
            return fallback
        }
        AppLog.probes.debug("BinaryLocator.shellPath() took ${elapsed}s")
        if (result.exitCode != 0) return fallback
        return shell.parsePathOutput(result.standardOutput).ifEmpty { fallback }
    }

    companion object {
        /** A hit stays a while; it is checked on every read, so an uninstall shows at once. */
        private const val FOUND_TTL = 600.0
        /** A miss expires sooner, so a CLI installed while the app runs is found without a restart. */
        private const val NOT_FOUND_TTL = 120.0
        private const val SHELL_PATH_TTL = 600.0
        private const val SHELL_PATH_KEY = "shellPath"

        /** The decision itself, free of file reads: `/bin/zsh` when the preferred shell has slices but no native one. */
        fun whichShellPath(preferred: String, machine: BinaryArchitecture, preferredSlices: List<BinaryArchitecture>?): String =
            if (preferredSlices == null || machine in preferredSlices) preferred else "/bin/zsh"

        /** Foundation's `.numeric` comparison: runs of digits compare as numbers. */
        fun numericCompare(a: String, b: String): Int {
            var i = 0
            var j = 0
            while (i < a.length && j < b.length) {
                if (a[i].isDigit() && b[j].isDigit()) {
                    val startA = i
                    val startB = j
                    while (i < a.length && a[i].isDigit()) i++
                    while (j < b.length && b[j].isDigit()) j++
                    val numberA = a.substring(startA, i).trimStart('0')
                    val numberB = b.substring(startB, j).trimStart('0')
                    if (numberA.length != numberB.length) return numberA.length.compareTo(numberB.length)
                    val order = numberA.compareTo(numberB)
                    if (order != 0) return order
                } else {
                    if (a[i] != b[j]) return a[i].compareTo(b[j])
                    i++
                    j++
                }
            }
            return (a.length - i).compareTo(b.length - j)
        }
    }
}
