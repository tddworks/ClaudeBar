package com.tddworks.claudebar.activity

import platform.posix.EPERM
import platform.posix.errno
import platform.posix.kill

/** Asks the kernel whether a process exists, without signalling it. */
internal class SystemProcessLiveness : ProcessLiveness {
    // Signal 0 delivers nothing but still checks the process exists; EPERM means it exists
    // but belongs to someone else, so it still runs.
    override fun isRunning(processId: Int): Boolean =
        processId > 0 && (kill(processId, 0) == 0 || errno == EPERM)
}
