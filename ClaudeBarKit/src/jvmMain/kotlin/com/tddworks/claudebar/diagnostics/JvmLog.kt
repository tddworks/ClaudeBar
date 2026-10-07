package com.tddworks.claudebar.diagnostics

// The JVM runs tests only (MODULAR_DESIGN §9): nothing is written unless a test installs a sink.
internal actual fun defaultLogSinks(): List<LogSink> = emptyList()

internal actual fun logsDirectoryPath(): String = System.getProperty("java.io.tmpdir") + "/ClaudeBar/Logs"
